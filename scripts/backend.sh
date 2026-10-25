#!/usr/bin/env bash
# yoyo.throttle backend — runs unprivileged as the shell user.
#
#   backend.sh settings-get              normalized settings JSON
#   backend.sh settings-set JSON         deep-merge a patch, print the result
#   backend.sh tick [--force]            apply if anything changed, print status JSON
#   backend.sh clear                     remove all shaping now (keeps settings)
#   backend.sh traffic                   per-app TCP rates since the last call (JSON)
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

# App key → process names (first one is the main process). Children of these
# processes inherit the same cgroup, so Heroic's legendary/gogdl/nile download
# helpers are covered by Heroic's cgroup; they are listed so a helper started
# on its own (e.g. legendary from a terminal) is still found.
declare -A APP_PROCS=(
  [heroic]="heroic legendary gogdl nile"
  [steam]="steam"
)
APP_ORDER=(heroic steam)
# tests: look for fake process names so a real Heroic/Steam doesn't leak in
[[ -n ${THROTTLE_PROCS_HEROIC:-} ]] && APP_PROCS[heroic]=$THROTTLE_PROCS_HEROIC
[[ -n ${THROTTLE_PROCS_STEAM:-} ]] && APP_PROCS[steam]=$THROTTLE_PROCS_STEAM

mkdir -p "$RUN" 2>/dev/null

defaults_json() {
  sed -e '/^\s*\/\//d' -e 's/^var CONFIG = //' -e 's/};\s*$/}/' "$here/../defaults.js"
}

# Normalize/clamp so the helper never sees a value it would reject.
NORMALIZE='
  def mbit: (tonumber? // 0) | floor | if . < 0 then 0 elif . > 10000 then 10000 else . end;
  def mib: (tonumber? // 4) | floor | if . < 1 then 1 elif . > 1024 then 1024 else . end;
  def app($d): {
    downMbit: ((.downMbit // $d.downMbit) | mbit),
    upMbit: ((.upMbit // $d.upMbit) | mbit),
    gamesSafe: (if (.gamesSafe | type) == "boolean" then .gamesSafe else $d.gamesSafe end),
    bulkMiB: ((.bulkMiB // $d.bulkMiB) | mib)
  };
  . as $s | $defaults as $d | {
    enabled: (if ($s.enabled | type) == "boolean" then $s.enabled else $d.enabled end),
    downMbit: (($s.downMbit // $d.downMbit) | mbit),
    upMbit: (($s.upMbit // $d.upMbit) | mbit),
    apps: ($d.apps | with_entries(.key as $k | .value = (($s.apps[$k] // {}) | app($d.apps[$k]))))
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

comm_of() { cat "/proc/$1/comm" 2>/dev/null; }

# app_cgroups KEY → lines "ok PATH" / "refused PATH REASON" / "shared PATH comm,comm"
app_cgroups() {
  local key=$1 name pid cg seen=" "
  for name in ${APP_PROCS[$key]}; do
    for pid in $(pgrep -x -u "$UID_" -- "$name" 2>/dev/null); do
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
        others=$(cg_others "$key" "$cg")
        [[ -n $others ]] && echo "shared $cg $others"
      fi
    done
  done
}

# Other programs living in the same cgroup (they get the same cap).
cg_others() {
  local key=$1 cg=$2 p c out=" " n=0
  # Launcher scripts and Steam runtime plumbing are part of the app itself.
  local mine=" ${APP_PROCS[$key]} bash sh steam.sh steamwebhelper reaper srt-logger steam-runtime-l srt-bwrap pv-adverb bwrap "
  while read -r p; do
    c=$(comm_of "$p") || continue
    [[ -n $c && $mine != *" $c "* && $out != *" $c "* ]] || continue
    out+="$c "; n=$((n + 1)); (( n >= 6 )) && break
  done < "$CG_ROOT/$cg/cgroup.procs" 2>/dev/null
  out=${out# }; out=${out% }
  printf '%s' "${out// /,}"
}

# Builds the helper argv into PLAN (array) and discovery info into DISCO (JSON).
build_plan() {
  local s iface enabled down up key cgs line kind path rest
  s=$(settings_get)
  iface=${THROTTLE_IFACE:-$(default_iface)}
  enabled=$(jq -r .enabled <<<"$s")
  down=$(jq -r '.downMbit * 1000' <<<"$s"); up=$(jq -r '.upMbit * 1000' <<<"$s")
  PLAN=(); DISCO='[]'; FPX=""
  local args=() any=0
  (( down > 0 || up > 0 )) && any=1
  for key in "${APP_ORDER[@]}"; do
    local a ad au mode mib running=false ok=() refused=() shared=()
    a=$(jq -c --arg k "$key" '.apps[$k]' <<<"$s")
    ad=$(jq -r '.downMbit * 1000' <<<"$a"); au=$(jq -r '.upMbit * 1000' <<<"$a")
    mode=$(jq -r 'if .gamesSafe then "bulk" else "all" end' <<<"$a"); mib=$(jq -r .bulkMiB <<<"$a")
    while read -r kind path rest; do
      [[ -n $kind ]] || continue
      running=true
      case $kind in
        ok) ok+=("$path") ;;
        refused) refused+=("$path:$rest") ;;
        shared) shared+=("$rest") ;;
      esac
    done < <(app_cgroups "$key")
    if (( ad > 0 || au > 0 )) && (( ${#ok[@]} )); then
      local joined; joined=$(IFS=,; echo "${ok[*]}")
      args+=(--app "$key:$ad:$au:$mode:$mib:$joined")
      any=1
      local p
      for p in "${ok[@]}"; do FPX+="$p@$(stat -c %i "$CG_ROOT/$p" 2>/dev/null);"; done
    fi
    DISCO=$(jq -c --arg k "$key" --argjson run "$running" \
      --argjson ok "$(printf '%s\n' "${ok[@]}" | jq -R . | jq -sc 'map(select(. != ""))')" \
      --argjson ref "$(printf '%s\n' "${refused[@]}" | jq -R . | jq -sc 'map(select(. != ""))')" \
      --argjson sh "$(printf '%s\n' "${shared[@]}" | tr ',' '\n' | jq -R . | jq -sc 'map(select(. != "")) | unique')" \
      '. + [{key: $k, running: $run, cgroups: $ok, refused: $ref, shared: $sh}]' <<<"$DISCO")
  done
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
APP_LABELS='heroic=Heroic legendary=Heroic gogdl=Heroic nile=Heroic steam=Steam steamwebhelper=Steam'

traffic() {
  local now prev_file=$RUN/ss.prev
  now=$(date +%s%N)
  local iface; iface=$(default_iface)
  local rx=0 tx=0
  if [[ -n $iface && -r /sys/class/net/$iface/statistics/rx_bytes ]]; then
    rx=$(< "/sys/class/net/$iface/statistics/rx_bytes"); tx=$(< "/sys/class/net/$iface/statistics/tx_bytes")
  fi
  local sample
  if [[ -n ${THROTTLE_SS_FIXTURE:-} ]]; then sample=$(cat "$THROTTLE_SS_FIXTURE")
  else sample=$(ss -tinpeH state established 2>/dev/null); fi
  {
    printf '#now %s %s %s\n' "$now" "$rx" "$tx"
    [[ -f $prev_file ]] && cat "$prev_file"
    printf '#cur\n'
    printf '%s\n' "$sample"
  } | awk -v labels="$APP_LABELS" -v uidtree="$USER_TREE" -v prevout="$prev_file.new" '
    function jstr(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
    BEGIN {
      n = split(labels, L, " "); for (i = 1; i <= n; i++) { split(L[i], kv, "="); label[kv[1]] = kv[2] }
      section = "head"
    }
    /^#now / { now = $2; rx = $3; tx = $4; next }
    /^#prev / { pnow = $2; prx = $3; ptx = $4; section = "prev"; next }
    /^#cur/ { section = "cur"; next }
    section == "prev" { pin[$1] = $2; pout[$1] = $3; next }
    section != "cur" { next }
    /^[^ \t]/ {
      ino = ""; name = ""; cg = ""
      if (match($0, /ino:[0-9]+/)) ino = substr($0, RSTART + 4, RLENGTH - 4)
      if (match($0, /users:\(\("[^"]+"/)) name = substr($0, RSTART + 9, RLENGTH - 10)
      if (match($0, /cgroup:[^ ]+/)) cg = substr($0, RSTART + 7, RLENGTH - 7)
      if (name == "") {
        # Not our process (root daemon etc.): label by its systemd unit.
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
      g = (name in label) ? label[name] : name
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
      printf "{\"interval\":%.2f,", dt
      if (dt > 0) printf "\"iface\":{\"down\":%d,\"up\":%d},", (rx - prx) / dt, (tx - ptx) / dt
      else printf "\"iface\":null,"
      printf "\"apps\":["
      first = 1
      for (g in conns) {
        d = (dt > 0) ? gin[g] / dt : 0; u = (dt > 0) ? gout[g] / dt : 0
        printf "%s{\"name\":%s,\"down\":%d,\"up\":%d,\"conns\":%d}", (first ? "" : ","), jstr(g), d, u, conns[g]
        first = 0
      }
      printf "]}\n"
    }' > "$RUN/traffic.json.tmp"
  { printf '#prev %s %s %s\n' "$now" "$rx" "$tx"; cat "$prev_file.new" 2>/dev/null; } > "$prev_file"
  rm -f "$prev_file.new"
  jq -c '.apps |= sort_by(-(.down + .up), .name)' "$RUN/traffic.json.tmp"
}

case ${1:-} in
  settings-get) settings_get ;;
  settings-set) settings_set "${2:-}" ;;
  tick) tick "${2:-}" ;;
  clear) cmd_clear ;;
  traffic) traffic ;;
  plan) build_plan; printf '%q ' "${PLAN[@]}"; echo; echo "$DISCO" ;;
  *) echo "usage: backend.sh settings-get|settings-set JSON|tick [--force]|clear|traffic|plan" >&2; exit 2 ;;
esac
