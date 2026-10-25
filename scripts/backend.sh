#!/usr/bin/env bash
# yoyo.throttle backend — runs unprivileged as the shell user.
#
#   backend.sh settings-get              normalized settings JSON
#   backend.sh settings-set JSON         deep-merge a patch, print the result
#   backend.sh tick [--force]            apply if anything changed, print status JSON
#   backend.sh clear                     remove all shaping now (keeps settings)
#   backend.sh traffic                   per-app TCP rates since the last call (JSON)
#   backend.sh stats-sample [--sync] [--print]  add bytes since the last sample to today's stats
#   backend.sh stats                     daily per-app / interface totals, last 30 days (JSON)
#   backend.sh stats-reset               forget all statistics
#   backend.sh plan                      what tick would pass to the helper (debug)
#
# The only privileged step is `sudo -n <helper> apply|clear`; the helper is
# installed once by scripts/install.sh. Everything here (process discovery,
# cgroups, ss, tc stats) works without root.
set -uo pipefail
export LC_ALL=C

readonly ID=yoyo.throttle
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${THROTTLE_HELPER:-/usr/local/lib/yoyo-throttle/throttle-helper}
SUDO=${THROTTLE_SUDO-sudo -n}
STATE_ROOT=${THROTTLE_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/$ID}
SETTINGS=$STATE_ROOT/settings.json
RUN=${THROTTLE_RUN_DIR:-${XDG_RUNTIME_DIR:-/tmp}/yoyo-throttle}
CG_ROOT=${THROTTLE_CGROUP_ROOT:-/sys/fs/cgroup}
UID_=${THROTTLE_UID:-$(id -u)}
USER_TREE="user.slice/user-$UID_.slice/user@$UID_.service/"
IFB=ifb-throttle

# Which processes belong to which app comes from the settings: the presets
# (Heroic incl. its legendary/gogdl/nile download helpers, Steam) are fixed in
# defaults.js, custom apps carry their own process names. Children inherit the
# main process's cgroup, so a launcher's helpers are covered by its cgroup;
# listing them also finds a helper that runs on its own.
# Tests: look for fake process names so a real Heroic/Steam doesn't leak in.
PROCS_OVERRIDE=$(jq -nc --arg h "${THROTTLE_PROCS_HEROIC:-}" --arg s "${THROTTLE_PROCS_STEAM:-}" \
  'def l: if . == "" then null else split(" ") end; {heroic: ($h | l), steam: ($s | l)}')

mkdir -p "$RUN" 2>/dev/null

defaults_json() {
  sed -e '/^\s*\/\//d' -e 's/^var CONFIG = //' -e 's/};\s*$/}/' "$here/../defaults.js"
}

# Normalize/clamp so the helper never sees a value it would reject. Unknown,
# malformed or over-limit custom apps are dropped; `"apps": {"key": null}` in a
# patch removes a custom app.
NORMALIZE='
  def mbit: (tonumber? // 0) | floor | if . < 0 then 0 elif . > 10000 then 10000 else . end;
  def mib: (tonumber? // 4) | floor | if . < 1 then 1 elif . > 1024 then 1024 else . end;
  def app($d): {
    downMbit: ((.downMbit // $d.downMbit) | mbit),
    upMbit: ((.upMbit // $d.upMbit) | mbit),
    gamesSafe: (if (.gamesSafe | type) == "boolean" then .gamesSafe else $d.gamesSafe end),
    bulkMiB: ((.bulkMiB // $d.bulkMiB) | mib)
  };
  def dedupe: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
  . as $s | $defaults as $d |
  (if ($s.apps | type) == "object" then $s.apps else {} end) as $sa |
  ($d.presets | to_entries | map(.key as $k | .value as $p |
    {key: $k, value: ((if ($sa[$k] | type) == "object" then $sa[$k] else {} end) | app($d.apps[$k]))
      + {label: $p.label, procs: $p.procs, preset: true}})) as $pre |
  ($sa | to_entries
    | map(select((.key | test("^[a-z][a-z0-9-]{0,15}$")) and ($d.presets[.key] == null) and ((.value | type) == "object")))
    | map(.key as $k | .value as $v
        | (if ($v.procs | type) == "array" then $v.procs else [] end)
          | map(select(type == "string" and test("^[A-Za-z0-9][A-Za-z0-9 ._+:-]{0,14}$")) | select(. as $p | $d.denyProcs | any(.[]; . == $p) | not))
          | dedupe | .[0:$d.limits.maxProcs] as $procs
        | select($procs | length > 0)
        | {key: $k, value: ($v | app($d.custom)) + {
            label: ((if ($v.label | type) == "string" then $v.label else "" end) | gsub("[[:cntrl:]]"; "") | sub("^\\s+"; "") | sub("\\s+$"; "") | .[0:32]
              | if . == "" then $procs[0] else . end),
            procs: $procs, preset: false}})
    | .[0:($d.limits.maxApps - ($pre | length))]) as $custom |
  {
    enabled: (if ($s.enabled | type) == "boolean" then $s.enabled else $d.enabled end),
    downMbit: (($s.downMbit // $d.downMbit) | mbit),
    upMbit: (($s.upMbit // $d.upMbit) | mbit),
    apps: (($pre + $custom) | from_entries)
  }'

settings_get() {
  local raw='{}'
  [[ -s $SETTINGS ]] && raw=$(cat "$SETTINGS")
  jq -c --argjson defaults "$(defaults_json)" "$NORMALIZE" <<<"$raw" 2>/dev/null ||
    jq -c --argjson defaults "$(defaults_json)" "$NORMALIZE" <<<'{}'
}

settings_set() {
  local patch=${1:-}
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$patch" || { echo '{"error":"patch must be a JSON object"}'; return 2; }
  mkdir -p "$STATE_ROOT"
  local next
  next=$(jq -c --argjson defaults "$(defaults_json)" --argjson p "$patch" ". * \$p | $NORMALIZE" <<<"$(settings_get)") || return 1
  printf '%s\n' "$next" > "$SETTINGS.tmp" && mv -f "$SETTINGS.tmp" "$SETTINGS"
  printf '%s\n' "$next"
}

default_iface() {
  local dev
  dev=$(ip -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')
  [[ -z $dev ]] && dev=$(ip -o -6 route get 2606:4700:4700::1111 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')
  printf '%s' "$dev"
}

comm_of() { local c; read -r c < "/proc/$1/comm" 2>/dev/null || return 1; printf '%s' "$c"; }

# One `ps` per tick: "pid<TAB>comm" for every process of ours (comm may hold spaces).
load_procs() {
  PROCS_TSV=$(ps -u "$UID_" -o pid=,comm= 2>/dev/null | sed -E 's/^ *([0-9]+) (.*)$/\1\t\2/')
}

# app_cgroups KEY "proc,proc" → lines "ok PATH" / "refused PATH REASON" / "shared PATH comm,comm"
app_cgroups() {
  local key=$1 procs=$2 pid comm cg seen=" "
  while IFS=$'\t' read -r pid comm; do
    [[ -n $pid && ",$procs," == *",$comm,"* ]] || continue
    cg=$(sed -n 's|^0::/||p' "/proc/$pid/cgroup" 2>/dev/null)
    [[ -n $cg && $seen != *" $cg "* ]] || continue
    seen+="$cg "
    if [[ $cg != "$USER_TREE"* ]]; then
      echo "refused $cg outside-user-manager"
    elif [[ $cg == *.slice || $cg == */init.scope || $cg == "$USER_TREE"session.slice/* ]]; then
      echo "refused $cg shared-system-unit"
    elif [[ ! $cg =~ ^[A-Za-z0-9@:._/\\-]+$ || ${#cg} -gt 400 ]]; then
      echo "refused $cg unsupported-name"
    else
      echo "ok $cg"
      local others
      others=$(cg_others "$procs" "$cg")
      [[ -n $others ]] && echo "shared $cg $others"
    fi
  done <<<"$PROCS_TSV"
}

# Other programs living in the same cgroup (they get the same cap).
cg_others() {
  local procs=$1 cg=$2 p c out="," n=0
  # Launcher scripts and Steam runtime plumbing are part of the app itself.
  local mine=",$procs,bash,sh,cat,steam.sh,steamwebhelper,reaper,srt-logger,steam-runtime-l,srt-bwrap,pv-adverb,bwrap,chrome_crashpad,crashpad_handle,"
  while read -r p; do
    c=$(comm_of "$p") || continue
    c=${c//,/}
    [[ -n $c && $mine != *",$c,"* && $out != *",$c,"* ]] || continue
    out+="$c,"; n=$((n + 1)); (( n >= 6 )) && break
  done < "$CG_ROOT/$cg/cgroup.procs" 2>/dev/null
  out=${out#,}; printf '%s' "${out%,}"
}

# App table from the settings: key<TAB>label<TAB>downKbit<TAB>upKbit<TAB>mode<TAB>mib<TAB>proc,proc
app_table() {
  jq -r --argjson ov "$PROCS_OVERRIDE" '.apps | to_entries[] | .key as $k
    | [$k, .value.label, (.value.downMbit * 1000), (.value.upMbit * 1000),
       (if .value.gamesSafe then "bulk" else "all" end), .value.bulkMiB,
       (($ov[$k] // .value.procs) | join(","))] | @tsv' <<<"$1"
}

# Builds the helper argv into PLAN (array) and discovery info into DISCO (JSON).
build_plan() {
  local s iface enabled down up key label ad au mode mib procs kind path rest
  s=$(settings_get)
  iface=${THROTTLE_IFACE:-$(default_iface)}
  read -r enabled down up < <(jq -r '[.enabled, .downMbit * 1000, .upMbit * 1000] | @tsv' <<<"$s")
  PLAN=(); FPX=""
  local args=() any=0 disco=""
  (( down > 0 || up > 0 )) && any=1
  load_procs
  while IFS=$'\t' read -r key label ad au mode mib procs; do
    [[ -n $key ]] || continue
    local running=false ok=() refused=() shared=""
    while read -r kind path rest; do
      [[ -n $kind ]] || continue
      running=true
      case $kind in
        ok) ok+=("$path") ;;
        refused) refused+=("$path:$rest") ;;
        shared) shared+="$rest," ;;
      esac
    done < <(app_cgroups "$key" "$procs")
    if (( ad > 0 || au > 0 )) && (( ${#ok[@]} )); then
      local joined; joined=$(IFS=,; echo "${ok[*]}")
      args+=(--app "$key:$ad:$au:$mode:$mib:$joined")
      any=1
      local p
      for p in "${ok[@]}"; do FPX+="$p@$(stat -c %i "$CG_ROOT/$p" 2>/dev/null);"; done
    fi
    disco+="$key"$'\t'"$running"$'\t'"$(IFS=$'\x1f'; echo "${ok[*]}")"$'\t'"$(IFS=$'\x1f'; echo "${refused[*]}")"$'\t'"${shared%,}"$'\n'
  done < <(app_table "$s")
  DISCO=$(printf '%s' "$disco" | jq -Rsc 'split("\n") | map(select(. != "") | split("\t")
    | {key: .[0], running: (.[1] == "true"),
       cgroups: (.[2] | split("\u001f") | map(select(. != ""))),
       refused: (.[3] | split("\u001f") | map(select(. != ""))),
       shared: (.[4] | split(",") | map(select(. != "")) | unique)})')
  IFACE=$iface
  if [[ $enabled != true || $any == 0 || -z $iface ]]; then
    PLAN=(clear)
  else
    PLAN=(apply --iface "$iface" --down "$down" --up "$up" "${args[@]}")
  fi
}

# What the kernel currently shows (readable without root).
live_state() {
  local iface=$1 ifb=false egress=false
  [[ -n ${THROTTLE_LIVE_FIXTURE:-} ]] && { cat "$THROTTLE_LIVE_FIXTURE"; return; }  # tests
  ip -o link show dev "$IFB" >/dev/null 2>&1 && ifb=true
  [[ -n $iface ]] && tc qdisc show dev "$iface" root 2>/dev/null | grep -q '^qdisc htb 1: ' && egress=true
  printf '{"ifb":%s,"egress":%s}' "$ifb" "$egress"
}

# Does the kernel still match what we applied last (e.g. after resume/reboot)?
live_matches() {
  local live=$1 want_down=0 want_up=0 a
  [[ ${PLAN[0]} == apply ]] || { [[ $live == '{"ifb":false,"egress":false}' ]]; return; }
  (( PLAN[4] > 0 )) && want_down=1
  (( PLAN[6] > 0 )) && want_up=1
  for a in "${PLAN[@]}"; do
    [[ $a == *:*:*:*:*:* ]] || continue
    IFS=: read -r _ d u _ <<<"$a"
    (( d > 0 )) && want_down=1
    (( u > 0 )) && want_up=1
  done
  [[ $live == "{\"ifb\":$([[ $want_down == 1 ]] && echo true || echo false),\"egress\":$([[ $want_up == 1 ]] && echo true || echo false)}" ]]
}

helper_state() {
  if [[ -x $HELPER ]]; then echo installed; else echo missing; fi
}

run_helper() {
  # shellcheck disable=SC2086
  $SUDO "$HELPER" "$@" 2>&1
}

tick() {
  local force=0; [[ ${1:-} == --force ]] && force=1
  build_plan
  local fp prev live hs result="" err="" applied=false called=false
  fp=$(printf '%s\n' "${PLAN[*]}" "$FPX" | md5sum | cut -d' ' -f1)
  prev=$(cat "$RUN/applied" 2>/dev/null)
  hs=$(helper_state)
  live=$(live_state "$IFACE")
  if [[ $hs == installed ]]; then
    if (( force )) || [[ $fp != "$prev" ]] || ! live_matches "$live"; then
      if [[ ${PLAN[0]} == clear && -z $prev && $live == '{"ifb":false,"egress":false}' ]] && (( ! force )); then
        echo "$fp" > "$RUN/applied"
      elif called=true; result=$(run_helper "${PLAN[@]}"); then
        echo "$fp" > "$RUN/applied"; rm -f "$RUN/error"
        live=$(live_state "$IFACE")
      else
        err=$(printf '%s' "$result" | tail -n 3)
        printf '%s' "$err" > "$RUN/error"
        rm -f "$RUN/applied"
      fi
    fi
  fi
  [[ -z $err && -f $RUN/error ]] && err=$(cat "$RUN/error")
  [[ $(cat "$RUN/applied" 2>/dev/null) == "$fp" ]] && applied=true
  jq -nc --arg helper "$hs" --arg iface "$IFACE" --arg mode "${PLAN[0]}" \
    --argjson applied "$applied" --argjson live "$live" --arg error "$err" \
    --argjson apps "$DISCO" --argjson changed "$called" --arg helperPath "$HELPER" \
    '{helper: $helper, helperPath: $helperPath, iface: $iface, mode: $mode, applied: $applied,
      live: $live, error: $error, apps: $apps, changed: $changed}'
}

cmd_clear() {
  [[ $(helper_state) == installed ]] || { echo '{"error":"helper not installed"}'; return 1; }
  local out
  if out=$(run_helper clear); then rm -f "$RUN/applied" "$RUN/error"; echo '{"ok":true}'
  else jq -nc --arg e "$out" '{error: $e}'; return 1; fi
}

# ---------------------------------------------------------------- traffic ---
# Per-socket TCP byte counters from `ss` (readable for our own processes and,
# without the process name, for everyone else's), diffed against the previous
# sample. Interface totals come from /sys. Loopback sockets never touch the
# network and are skipped.

netdev_counts() {
  if [[ -n ${THROTTLE_NETDEV_FIXTURE:-} ]]; then cat "$THROTTLE_NETDEV_FIXTURE"; return; fi  # tests
  local iface rx=0 tx=0
  iface=$(default_iface)
  if [[ -n $iface && -r /sys/class/net/$iface/statistics/rx_bytes ]]; then
    rx=$(< "/sys/class/net/$iface/statistics/rx_bytes"); tx=$(< "/sys/class/net/$iface/statistics/tx_bytes")
  fi
  printf '%s %s %s\n' "${iface:--}" "$rx" "$tx"
}

# process name → app key + label, from the settings (one line per process name)
label_table() {
  jq -r --argjson ov "$PROCS_OVERRIDE" '.apps | to_entries[] | .key as $k | .value.label as $l
    | (($ov[$k] // []) + .value.procs)[] | [., $k, $l] | @tsv' <<<"$(settings_get)"
}

# ss_deltas PREV_FILE MODE   MODE=rates → traffic JSON, MODE=bytes → TSV for stats
ss_deltas() {
  local prev_file=$1 mode=$2 now iface rx tx sample
  now=$(date +%s%N)
  read -r iface rx tx < <(netdev_counts)
  if [[ -n ${THROTTLE_SS_FIXTURE:-} ]]; then sample=$(cat "$THROTTLE_SS_FIXTURE")
  else sample=$(ss -tinpeH state established 2>/dev/null); fi
  {
    printf '#now %s %s %s %s\n' "$now" "$iface" "$rx" "$tx"
    [[ -f $prev_file ]] && cat "$prev_file"
    printf '#cur\n'
    printf '%s\n' "$sample"
  } | YT_LABELS=$(label_table) awk -v mode="$mode" -v maxgap="${THROTTLE_STATS_MAXGAP_S:-900}" -v prevout="$prev_file.new" '
    # comm is cut at 15 chars ("telegram-deskto"); show the executable name
    # instead when it starts with the same text ("telegram-desktop").
    function fullname(n, p,   f, line) {
      if (length(n) < 15 || p == "" || ENVIRON["THROTTLE_SS_FIXTURE"] != "") return n
      f = "/proc/" p "/cmdline"
      RS_save = RS; RS = "\0"
      if ((getline line < f) > 0) { sub(/.*\//, "", line) }
      close(f); RS = RS_save
      if (line != "" && line ~ /^[A-Za-z0-9][A-Za-z0-9 ._+:-]*$/ && length(line) <= 32 && tolower(substr(line, 1, 15)) == tolower(n)) return line
      return n
    }
    function jstr(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
    BEGIN {
      n = split(ENVIRON["YT_LABELS"], L, "\n")
      for (i = 1; i <= n; i++) if (split(L[i], f, "\t") == 3) { lkey[f[1]] = f[2]; llab[f[1]] = f[3] }
      section = "head"
    }
    /^#now / { now = $2; iface = $3; rx = $4; tx = $5; next }
    /^#prev / { pnow = $2; piface = $3; prx = $4; ptx = $5; section = "prev"; next }
    /^#cur/ { section = "cur"; next }
    section == "prev" { pin[$1] = $2; pout[$1] = $3; next }
    section != "cur" { next }
    /^[^ \t]/ {
      ino = ""; name = ""; cg = ""; own = 1; pid = ""
      if ($4 ~ /^(127\.|\[::1\]|\[::ffff:127\.)/) next
      if (match($0, /ino:[0-9]+/)) ino = substr($0, RSTART + 4, RLENGTH - 4)
      if (match($0, /users:\(\("[^"]+"/)) name = substr($0, RSTART + 9, RLENGTH - 10)
      if (match($0, /",pid=[0-9]+/)) pid = substr($0, RSTART + 6, RLENGTH - 6)
      if (match($0, /cgroup:[^ ]+/)) cg = substr($0, RSTART + 7, RLENGTH - 7)
      if (name == "") {
        # Not our process (root daemon etc.): label by its systemd unit.
        own = 0
        unit = cg; sub(/.*\//, "", unit); sub(/\.(service|scope)$/, "", unit)
        name = (unit == "" ? "other" : unit)
      }
      next
    }
    {
      if (ino == "") next
      bin = 0; bout = 0
      if (match($0, /bytes_received:[0-9]+/)) bin = substr($0, RSTART + 15, RLENGTH - 15)
      if (match($0, /bytes_acked:[0-9]+/)) bout = substr($0, RSTART + 12, RLENGTH - 12)
      print ino, bin, bout > prevout
      g = (own && (name in llab)) ? llab[name] : name
      if (!(g in conns)) { gkey[g] = (own && (name in lkey)) ? lkey[name] : ""; gown[g] = own; gproc[g] = name; gfull[g] = fullname(name, pid) }
      if (pnow != "") {
        din = (ino in pin) ? bin - pin[ino] : bin
        dout = (ino in pout) ? bout - pout[ino] : bout
        if (din < 0) din = 0; if (dout < 0) dout = 0
        gin[g] += din; gout[g] += dout
      }
      conns[g]++
      ino = ""
    }
    END {
      close(prevout)
      dt = (pnow != "") ? (now - pnow) / 1e9 : 0
      ok = (dt > 0 && piface == iface && iface != "-" && rx >= prx && tx >= ptx)
      if (mode == "bytes") {
        # No previous sample, or it is so old (shell was off, suspend) that the
        # gap cannot be attributed to a day: this sample only sets the baseline.
        if (pnow == "" || dt > maxgap) exit
        printf "#iface\t%d\t%d\t%d\n", (ok ? rx - prx : 0), (ok ? tx - ptx : 0), ok
        for (g in conns) if (gin[g] + gout[g] > 0) printf "%s\t%d\t%d\n", g, gin[g], gout[g]
        exit
      }
      printf "{\"interval\":%.2f,", dt
      if (ok) printf "\"iface\":{\"name\":%s,\"down\":%d,\"up\":%d},", jstr(iface), (rx - prx) / dt, (tx - ptx) / dt
      else printf "\"iface\":null,"
      printf "\"apps\":["
      first = 1
      for (g in conns) {
        d = (dt > 0) ? gin[g] / dt : 0; u = (dt > 0) ? gout[g] / dt : 0
        printf "%s{\"name\":%s,\"key\":%s,\"proc\":%s,\"full\":%s,\"own\":%s,\"down\":%d,\"up\":%d,\"conns\":%d}", (first ? "" : ","),
          jstr(g), jstr(gkey[g]), jstr(gproc[g]), jstr(gfull[g]), (gown[g] ? "true" : "false"), d, u, conns[g]
        first = 0
      }
      printf "]}\n"
    }'
  { printf '#prev %s %s %s %s\n' "$now" "$iface" "$rx" "$tx"; cat "$prev_file.new" 2>/dev/null; } > "$prev_file"
  rm -f "$prev_file.new"
}

traffic() {
  ss_deltas "$RUN/ss.prev" rates > "$RUN/traffic.json.tmp"
  jq -c '.apps |= sort_by(-(.down + .up), .name)' "$RUN/traffic.json.tmp"
}

# ------------------------------------------------------------------ stats ---
# Daily byte totals per app and for the interface:
#   {"v":1,"days":{"2026-10-25":{"rx":N,"tx":N,"apps":{"Heroic":[down,up],...}}}}
# The live copy sits in $RUN (tmpfs) and is written to $STATE_ROOT every 5 min,
# so a crash or reboot loses at most that much. Days older than keepDays are
# dropped; a day keeps at most 40 names (the rest fold into "Other apps").
STATS=$STATE_ROOT/stats.json
STATS_LIVE=$RUN/stats.json
STATS_SYNC_S=${THROTTLE_STATS_SYNC_S:-300}

stats_today() { printf '%s' "${THROTTLE_TODAY:-$(date +%F)}"; }

stats_load() {
  [[ -s $STATS_LIVE ]] && jq -e '.days | type == "object"' "$STATS_LIVE" >/dev/null 2>&1 && return
  if [[ -s $STATS ]] && jq -e '.days | type == "object"' "$STATS" >/dev/null 2>&1; then cp -f "$STATS" "$STATS_LIVE"
  else echo '{"v":1,"days":{}}' > "$STATS_LIVE"; fi
}

stats_sync() {
  mkdir -p "$STATE_ROOT"
  cp -f "$STATS_LIVE" "$STATS.tmp" && mv -f "$STATS.tmp" "$STATS"
  date +%s > "$RUN/stats.synced"
}

stats_sample() {
  # The Service timer and a shell-exit sync may overlap; one writer at a time.
  exec 9>"$RUN/stats.lock"
  flock -w 5 9 || return 0
  stats_load
  local deltas today cutoff keep
  deltas=$(ss_deltas "$RUN/stats.prev" bytes)
  today=$(stats_today)
  keep=$(defaults_json | jq -r .limits.keepDays)
  cutoff=$(date -d "$today -$keep days" +%F)
  if [[ -n $deltas ]]; then
    jq -c --arg day "$today" --arg cutoff "$cutoff" --arg d "$deltas" '
      ($d | split("\n") | map(select(. != "") | split("\t"))) as $rows
      | ($rows | map(select(.[0] == "#iface")) | .[0] // ["#iface", "0", "0"]) as $if
      | .days[$day] //= {rx: 0, tx: 0, apps: {}}
      | .days[$day].rx += ($if[1] | tonumber) | .days[$day].tx += ($if[2] | tonumber)
      | reduce ($rows[] | select(.[0] != "#iface")) as $r (.;
          .days[$day].apps[$r[0]] = [((.days[$day].apps[$r[0]][0] // 0) + ($r[1] | tonumber)),
                                     ((.days[$day].apps[$r[0]][1] // 0) + ($r[2] | tonumber))])
      | .days[$day].apps |= (if length > 40 then
          (to_entries | sort_by(-(.value[0] + .value[1]))) as $e
          | ($e[:39] | from_entries) + {"Other apps": ($e[39:] | reduce .[] as $x ([0, 0]; [.[0] + $x.value[0], .[1] + $x.value[1]]))}
        else . end)
      | .days |= with_entries(select(.key >= $cutoff))' "$STATS_LIVE" > "$STATS_LIVE.tmp" &&
      mv -f "$STATS_LIVE.tmp" "$STATS_LIVE"
  fi
  local last; last=$(cat "$RUN/stats.synced" 2>/dev/null || echo 0)
  if [[ ${1:-} == --sync ]] || (( $(date +%s) - last >= STATS_SYNC_S )); then stats_sync; fi
  [[ ${1:-} == --print || ${2:-} == --print ]] && stats_print
  return 0
}

# Last 30 days, oldest first, apps sorted by volume: what the Stats tab draws.
stats_print() {
  stats_load
  jq -c --arg today "$(stats_today)" '{today: $today,
    days: (.days | to_entries | sort_by(.key) | .[-30:] | map({date: .key, rx: .value.rx, tx: .value.tx,
      apps: (.value.apps | to_entries | map({name: .key, down: .value[0], up: .value[1]}) | sort_by(-(.down + .up)))}))}' "$STATS_LIVE"
}

case ${1:-} in
  settings-get) settings_get ;;
  settings-set) settings_set "${2:-}" ;;
  tick) tick "${2:-}" ;;
  clear) cmd_clear ;;
  traffic) traffic ;;
  stats-sample) stats_sample "${2:-}" "${3:-}" ;;
  stats) stats_print ;;
  stats-reset) rm -f "$STATS" "$STATS_LIVE" "$RUN/stats.prev" "$RUN/stats.synced"; echo '{"ok":true}' ;;
  plan) build_plan; printf '%q ' "${PLAN[@]}"; echo; echo "$DISCO" ;;
  *) echo "usage: backend.sh settings-get|settings-set JSON|tick [--force]|clear|traffic|stats-sample [--sync] [--print]|stats|stats-reset|plan" >&2; exit 2 ;;
esac
