#!/usr/bin/env bash
# End-to-end shaping test without root: user+net namespaces, a veth pair,
# real systemd --user scopes for cgroup matching, and the real helper.
#
#   tests/netns-e2e.sh            run all cases
#
# Topology:  [srv ns] vs 10.9.0.1  <==veth==>  vc 10.9.0.2 [cli ns]
# The helper shapes "vc" in the cli namespace exactly like it would shape
# enp42s0 on the host (ingress via ifb + htb, egress via htb, nft cgroup marks).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
helper=$here/../helper/throttle-helper
work=$(mktemp -d /tmp/yt-e2e.XXXXXX)
uid=$(id -u)
slice=yttest.slice
cgbase="user.slice/user-$uid.slice/user@$uid.service/yttest.slice"
pass=0; fail=0

cleanup() {
  [[ -n ${holder:-} ]] && { kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; }
  systemctl --user stop yttest.slice >/dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

# --- namespaces -------------------------------------------------------------
cat > "$work/setup.sh" <<'IN'
set -e
trap 'kill $(jobs -p) 2>/dev/null; exit 0' TERM INT
mount -t tmpfs tmpfs /run && mkdir -p /run/netns
ip netns add srv; ip netns add cli
ip link add vs netns srv type veth peer name vc netns cli
ip -n srv addr add 10.9.0.1/24 dev vs; ip -n srv link set vs up; ip -n srv link set lo up
ip -n cli addr add 10.9.0.2/24 dev vc; ip -n cli link set vc up; ip -n cli link set lo up
# The veth is ~unlimited; give the server a realistic 200 Mbit "ISP line".
nsenter --net=/run/netns/srv tc qdisc add dev vs root tbf rate 200mbit burst 256kb latency 50ms
nsenter --net=/run/netns/srv python3 "$1/netns-server.py" &
nsenter --net=/run/netns/cli sleep infinity &
echo $! > "$2/cli.pid"
wait
IN
unshare -rnm --propagation private bash "$work/setup.sh" "$here" "$work" &
holder=$!
for _ in $(seq 50); do [[ -s $work/cli.pid ]] && break; sleep 0.1; done
cli=$(cat "$work/cli.pid")
sleep 0.5

in_cli() { nsenter -t "$cli" -U -n --preserve-credentials "$@"; }
as_root_in_cli() { nsenter -t "$cli" -U -n --preserve-credentials "$@"; }
helper_run() {
  as_root_in_cli env THROTTLE_TEST=1 THROTTLE_TEST_UID="$uid" THROTTLE_STATE_DIR="$work/state" bash "$helper" "$@"
}

# Long-lived scope per fake app; commands get injected by writing PIDs into
# the scope's cgroup (we own our delegated systemd --user subtree).
start_scope() {
  systemd-run --user --quiet --collect --scope --slice="$slice" --unit="yt-$1" sleep 600 >/dev/null 2>&1 &
  for _ in $(seq 50); do [[ -d /sys/fs/cgroup/$cgbase/yt-$1.scope ]] && return 0; sleep 0.1; done
  echo "scope yt-$1 did not appear" >&2; return 1
}
in_scope() { # in_scope NAME cmd...   (runs cmd inside scope NAME and cli netns)
  local name=$1; shift
  bash -c 'echo $$ > "$0/cgroup.procs" && exec "$@"' "/sys/fs/cgroup/$cgbase/yt-$name.scope" \
    nsenter -t "$cli" -U -n --preserve-credentials "$@"
}
mbit_get() { # mbit_get SCOPE BYTES
  in_scope "$1" curl -s -o /dev/null -w '%{speed_download}' "http://10.9.0.1:9000/$2" | awk '{printf "%.1f", $1*8/1e6}'
}
mbit_put() {
  head -c "$2" /dev/zero > "$work/up.bin"
  in_scope "$1" curl -s -o /dev/null -T "$work/up.bin" -w '%{speed_upload}' http://10.9.0.1:9000/up | awk '{printf "%.1f", $1*8/1e6}'
}
check() { # check LABEL VALUE MIN MAX
  if awk -v v="$2" -v a="$3" -v b="$4" 'BEGIN{exit !(v>=a && v<=b)}'; then
    printf 'PASS  %-58s %6s Mbit/s (want %s..%s)\n' "$1" "$2" "$3" "$4"; pass=$((pass+1))
  else
    printf 'FAIL  %-58s %6s Mbit/s (want %s..%s)\n' "$1" "$2" "$3" "$4"; fail=$((fail+1))
  fi
}

# The heroic scope name carries a systemd "\x2d" escape, like the real
# app-Hyprland-gtk\x2dlaunch-*.scope units Omarchy's launcher creates.
H='heroic\x2dgl'
start_scope "$H"; start_scope steam; start_scope other
HC="$cgbase/yt-$H.scope"; SC="$cgbase/yt-steam.scope"
MB=$((1024*1024))

echo "== baseline (no shaping)"
check "baseline download, other app" "$(mbit_get other $((40*MB)))" 150 210

echo "== global download cap 50 Mbit/s"
helper_run apply --iface vc --down 50000 --up 0 >/dev/null || echo "apply failed"
check "global 50: download, other app" "$(mbit_get other $((25*MB)))" 40 52

echo "== per-app: heroic 10 Mbit/s (mode all), global off"
helper_run apply --iface vc --down 0 --up 0 --app "heroic:10000:0:all:4:$HC" >/dev/null || echo "apply failed"
check "heroic capped download" "$(mbit_get "$H" $((10*MB)))" 8 10.6
check "other app not capped" "$(mbit_get other $((40*MB)))" 150 210

echo "== per-app concurrent: heroic 10 + other at the same time"
( mbit_get "$H" $((12*MB)) > "$work/h.out" ) & bg=$!
o=$(mbit_get other $((60*MB)))
wait "$bg"
check "concurrent: heroic stays capped" "$(cat "$work/h.out")" 8 10.6
check "concurrent: other gets the rest" "$o" 140 210

echo "== full pipeline: backend.sh tick finds a running 'heroic' and drives the helper"
cp /usr/bin/sleep "$work/yt-heroic"
bash -c 'echo $$ > "$0/cgroup.procs" && exec "$1" 300' "/sys/fs/cgroup/$HC" "$work/yt-heroic" & fakeheroic=$!
sleep 0.3
export THROTTLE_PROCS_HEROIC=yt-heroic THROTTLE_PROCS_STEAM=yt-steam-none THROTTLE_STATE_ROOT=$work/bstate THROTTLE_RUN_DIR=$work/brun THROTTLE_IFACE=vc THROTTLE_HELPER=$helper \
  THROTTLE_SUDO="nsenter -t $cli -U -n --preserve-credentials env THROTTLE_TEST=1 THROTTLE_TEST_UID=$uid THROTTLE_STATE_DIR=$work/state bash"
helper_run clear >/dev/null
bash "$here/../scripts/backend.sh" settings-set '{"apps":{"heroic":{"downMbit":15,"gamesSafe":false}}}' >/dev/null
st=$(bash "$here/../scripts/backend.sh" tick)
if [[ $(jq -r --arg cg "$HC" '[.applied, .apps[0].running, (.apps[0].cgroups == [$cg])] | join(",")' <<<"$st") == "true,true,true" ]]; then
  echo "PASS  tick applied with heroic's cgroup"; pass=$((pass+1))
else echo "FAIL  tick: $st"; fail=$((fail+1)); fi
check "heroic capped at 15 via backend" "$(mbit_get "$H" $((12*MB)))" 12 16
check "other app untouched via backend" "$(mbit_get other $((40*MB)))" 150 210
kill "$fakeheroic" 2>/dev/null; wait "$fakeheroic" 2>/dev/null
unset THROTTLE_PROCS_HEROIC THROTTLE_PROCS_STEAM THROTTLE_STATE_ROOT THROTTLE_RUN_DIR THROTTLE_IFACE THROTTLE_HELPER THROTTLE_SUDO

echo "== bulk mode: steam 10 Mbit/s only for TCP flows > 4 MiB"
helper_run apply --iface vc --down 0 --up 0 --app "steam:10000:0:bulk:4:$SC" >/dev/null || echo "apply failed"
check "steam small 2 MiB TCP (under threshold) not capped" "$(mbit_get steam $((2*MB)))" 60 260
check "steam large 40 MiB TCP download capped" "$(mbit_get steam $((40*MB)))" 8 13
check "steam UDP 40 Mbit/s 'game' stream not capped" "$(in_scope steam python3 "$here/udp-client.py" 10.9.0.1)" 34 42

echo "== same in mode all: UDP is capped (proves the bulk rule is what protects games)"
helper_run apply --iface vc --down 0 --up 0 --app "steam:10000:0:all:4:$SC" >/dev/null || echo "apply failed"
check "steam UDP stream capped in mode all" "$(in_scope steam python3 "$here/udp-client.py" 10.9.0.1)" 5 11

echo "== upload caps: global 20 Mbit/s up, heroic 5 Mbit/s up"
helper_run apply --iface vc --down 0 --up 20000 --app "heroic:0:5000:all:4:$HC" >/dev/null || echo "apply failed"
check "heroic upload capped at 5" "$(mbit_put "$H" $((4*MB)))" 4 5.4
check "other upload capped at global 20" "$(mbit_put other $((15*MB)))" 17 21

echo "== clear"
helper_run clear >/dev/null
check "after clear: back to line rate" "$(mbit_get other $((40*MB)))" 150 210
left=$(as_root_in_cli bash -c 'tc qdisc show dev vc; ip link show ifb-throttle 2>/dev/null; nft list tables')
if grep -qE 'htb|ingress|ifb-throttle|yoyo_throttle' <<<"$left"; then echo "FAIL  leftovers after clear: $left"; fail=$((fail+1)); else echo "PASS  nothing left behind after clear"; pass=$((pass+1)); fi

echo
echo "passed $pass, failed $fail"
(( fail == 0 ))
