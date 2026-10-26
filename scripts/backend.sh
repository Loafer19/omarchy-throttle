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
IFB="ifb-throttle"
LIB=$here/lib
readonly LIVE_NONE='{"ifb":false,"egress":false}'  # live_state with nothing shaped

# Which processes belong to which app comes from the settings: the presets
# (Heroic incl. its legendary/gogdl/nile download helpers, Steam) are fixed in
# defaults.js, custom apps carry their own process names. Children inherit the
# main process's cgroup, so a launcher's helpers are covered by its cgroup;
# listing them also finds a helper that runs on its own.
# Tests: look for fake process names so a real Heroic/Steam doesn't leak in.
PROCS_OVERRIDE=$(jq -nc --arg h "${THROTTLE_PROCS_HEROIC:-}" --arg s "${THROTTLE_PROCS_STEAM:-}" \
  'def l: if . == "" then null else split(" ") end; {heroic: ($h | l), steam: ($s | l)}')

mkdir -p "$RUN" 2>/dev/null

json_error() { jq -nc --arg e "$1" '{error: $e}'; }
jbool() { if (( $1 )); then echo true; else echo false; fi; }

defaults_json() {
  sed -e '/^\s*\/\//d' -e 's/^var CONFIG = //' -e 's/};\s*$/}/' "$here/../defaults.js"
}

# Normalize/clamp so the helper never sees a value it would reject. Unknown,
# malformed or over-limit custom apps are dropped; `"apps": {"key": null}` in a
# patch removes a custom app (rules: scripts/lib/normalize.jq).
# normalize [PATCH]: stdin settings (deep-merged with PATCH) → normalized JSON.
normalize() {
  # shellcheck disable=SC2016  # jq variables, not shell ones
  jq -c -L "$LIB" --argjson defaults "$(defaults_json)" --argjson p "${1:-null}" \
    'include "normalize"; (if $p == null then . else . * $p end) | normalize($defaults)'
}

settings_get() {
  local raw='{}'
  [[ -s $SETTINGS ]] && raw=$(cat "$SETTINGS")
  normalize <<<"$raw" 2>/dev/null || normalize <<<'{}'
}

settings_set() {
  local patch=${1:-}
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$patch" || { json_error "patch must be a JSON object"; return 2; }
  mkdir -p "$STATE_ROOT"
  local next
  next=$(normalize "$patch" <<<"$(settings_get)") || return 1
  printf '%s\n' "$next" > "$SETTINGS.tmp" && mv -f "$SETTINGS.tmp" "$SETTINGS"
  printf '%s\n' "$next"
}

# route_dev -4|-6 ADDR → the device the kernel routes ADDR through
route_dev() { ip -o "$1" route get "$2" 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p'; }

default_iface() {
  local dev
  dev=$(route_dev -4 1.1.1.1)
  [[ -z $dev ]] && dev=$(route_dev -6 2606:4700:4700::1111)
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

# collect_cgroups KEY "proc,proc" → CG_RUNNING (true/false), CG_OK, CG_REFUSED
# (arrays) and CG_SHARED ("comm,comm,") from app_cgroups.
collect_cgroups() {
  local kind path rest
  CG_RUNNING=false; CG_OK=(); CG_REFUSED=(); CG_SHARED=""
  while read -r kind path rest; do
    [[ -n $kind ]] || continue
    CG_RUNNING=true
    case $kind in
      ok) CG_OK+=("$path") ;;
      refused) CG_REFUSED+=("$path:$rest") ;;
      shared) CG_SHARED+="$rest," ;;
    esac
  done < <(app_cgroups "$1" "$2")
}

# Discovery TSV (key, running, cgroups, refused, shared) → the status "apps" JSON.
disco_json() {
  jq -Rsc 'split("\n") | map(select(. != "") | split("\t")
    | {key: .[0], running: (.[1] == "true"),
       cgroups: (.[2] | split("\u001f") | map(select(. != ""))),
       refused: (.[3] | split("\u001f") | map(select(. != ""))),
       shared: (.[4] | split(",") | map(select(. != "")) | unique)})'
}

# Builds the helper argv into PLAN (array) and discovery info into DISCO (JSON).
build_plan() {
  local s iface enabled down up key ad au mode mib procs p
  s=$(settings_get)
  iface=${THROTTLE_IFACE:-$(default_iface)}
  read -r enabled down up < <(jq -r '[.enabled, .downMbit * 1000, .upMbit * 1000] | @tsv' <<<"$s")
  PLAN=(); FPX=""
  local args=() any=0 disco=""
  (( down > 0 || up > 0 )) && any=1
  load_procs
  while IFS=$'\t' read -r key _ ad au mode mib procs; do
    [[ -n $key ]] || continue
    collect_cgroups "$key" "$procs"
    if (( ad > 0 || au > 0 )) && (( ${#CG_OK[@]} )); then
      args+=(--app "$key:$ad:$au:$mode:$mib:$(IFS=,; echo "${CG_OK[*]}")")
      any=1
      for p in "${CG_OK[@]}"; do FPX+="$p@$(stat -c %i "$CG_ROOT/$p" 2>/dev/null);"; done
    fi
    disco+="$key"$'\t'"$CG_RUNNING"$'\t'"$(IFS=$'\x1f'; echo "${CG_OK[*]}")"$'\t'"$(IFS=$'\x1f'; echo "${CG_REFUSED[*]}")"$'\t'"${CG_SHARED%,}"$'\n'
  done < <(app_table "$s")
  DISCO=$(printf '%s' "$disco" | disco_json)
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
  [[ ${PLAN[0]} == apply ]] || { [[ $live == "$LIVE_NONE" ]]; return; }
  (( PLAN[4] > 0 )) && want_down=1
  (( PLAN[6] > 0 )) && want_up=1
  for a in "${PLAN[@]}"; do
    [[ $a == *:*:*:*:*:* ]] || continue
    IFS=: read -r _ d u _ <<<"$a"
    (( d > 0 )) && want_down=1
    (( u > 0 )) && want_up=1
  done
  [[ $live == "{\"ifb\":$(jbool $want_down),\"egress\":$(jbool $want_up)}" ]]
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
      if [[ ${PLAN[0]} == clear && -z $prev && $live == "$LIVE_NONE" ]] && (( ! force )); then
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
  [[ $(helper_state) == installed ]] || { json_error "helper not installed"; return 1; }
  local out
  if out=$(run_helper clear); then rm -f "$RUN/applied" "$RUN/error"; echo '{"ok":true}'
  else json_error "$out"; return 1; fi
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
  } | YT_LABELS=$(label_table) awk -v mode="$mode" -v maxgap="${THROTTLE_STATS_MAXGAP_S:-900}" -v prevout="$prev_file.new" \
    -f "$LIB/ss-deltas.awk"
  local rc=$?
  { printf '#prev %s %s %s %s\n' "$now" "$iface" "$rx" "$tx"; cat "$prev_file.new" 2>/dev/null; } > "$prev_file"
  rm -f "$prev_file.new"
  return "$rc"
}

traffic() {
  ss_deltas "$RUN/ss.prev" rates > "$RUN/traffic.json.tmp" || return 1
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

stats_valid() { [[ -s $1 ]] && jq -e '.days | type == "object"' "$1" >/dev/null 2>&1; }

stats_load() {
  stats_valid "$STATS_LIVE" && return
  if stats_valid "$STATS"; then cp -f "$STATS" "$STATS_LIVE"
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
  deltas=$(ss_deltas "$RUN/stats.prev" bytes) || deltas=""  # bad sample: count nothing
  today=$(stats_today)
  keep=$(settings_get | jq -r .keepDays)  # normalized: always set, 1..365
  cutoff=$(date -d "$today -$keep days" +%F)
  if [[ -n $deltas ]]; then
    jq -c --arg day "$today" --arg cutoff "$cutoff" --arg d "$deltas" -f "$LIB/stats-add.jq" "$STATS_LIVE" > "$STATS_LIVE.tmp" &&
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
