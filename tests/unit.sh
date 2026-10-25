#!/usr/bin/env bash
# Unprivileged unit tests for scripts/backend.sh and helper validation.
#   tests/unit.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$here/..
backend=$root/scripts/backend.sh
helper=$root/helper/throttle-helper
tmp=$(mktemp -d /tmp/yt-unit.XXXXXX)
uid=$(id -u)
pass=0; fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }
expect() { # expect LABEL ACTUAL EXPECTED
  if [[ $2 == "$3" ]]; then ok "$1"; else no "$1" "got: $2 | want: $3"; fi
}
expect_has() { if [[ $2 == *"$3"* ]]; then ok "$1"; else no "$1" "missing: $3"; fi; }
expect_match() { if [[ $2 =~ $3 ]]; then ok "$1"; else no "$1" "got: $2 | want ~ $3"; fi; }
cleanup() {
  systemctl --user stop yt-unit-heroic.scope yt-unit-torrent.scope >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT

export THROTTLE_PROCS_HEROIC=yt-heroic THROTTLE_PROCS_STEAM=yt-steam-none
export THROTTLE_STATE_ROOT=$tmp/state THROTTLE_RUN_DIR=$tmp/run THROTTLE_IFACE=eth-test
B() { bash "$backend" "$@"; }

echo "== settings"
expect "defaults when no file" "$(B settings-get | jq -c '[.enabled,.downMbit,.apps.heroic.gamesSafe,.apps.steam.bulkMiB]')" '[true,0,true,4]'
B settings-set '{"downMbit":50,"apps":{"heroic":{"downMbit":10}}}' >/dev/null
expect "deep merge keeps siblings" "$(B settings-get | jq -c '[.downMbit,.apps.heroic.downMbit,.apps.heroic.gamesSafe,.apps.steam.downMbit]')" '[50,10,true,0]'
B settings-set '{"downMbit":-5,"upMbit":999999,"apps":{"steam":{"bulkMiB":0,"gamesSafe":"yes"},"evil":{"downMbit":1}}}' >/dev/null
expect "clamps and drops unknown apps" "$(B settings-get | jq -c '[.downMbit,.upMbit,.apps.steam.bulkMiB,.apps.steam.gamesSafe,(.apps|keys)]')" '[0,10000,1,true,["heroic","steam"]]'
out=$(B settings-set '[1]'); rc=$?
expect "rejects non-object patch" "$out rc=$rc" '{"error":"patch must be a JSON object"} rc=2'
echo "== any app (custom apps in settings)"
B settings-set '{"apps":{"qbit":{"label":"  Q\u0001bit  ","procs":["qbittorrent","bash","a/b","qbittorrent","x;y"],"downMbit":5},"Bad Key":{"procs":["x"]},"shells":{"procs":["bash","sudo"]},"heroic":{"procs":["bash"],"label":"Evil"},"str":"x"}}' >/dev/null
expect "custom app normalized (label, procs, denylist)" "$(B settings-get | jq -c '.apps.qbit | [.label,.procs,.downMbit,.gamesSafe,.preset]')" '["Qbit",["qbittorrent"],5,false,false]'
expect "bad keys / denied-only / non-objects dropped, presets fixed" "$(B settings-get | jq -c '[(.apps|keys_unsorted), .apps.heroic.label, .apps.heroic.procs[0]]')" '[["heroic","steam","qbit"],"Heroic","heroic"]'
B settings-set '{"apps":{"a1":{"procs":["a1"]},"a2":{"procs":["a2"]},"a3":{"procs":["a3"]},"a4":{"procs":["a4"]},"a5":{"procs":["a5"]},"a6":{"procs":["a6"]}}}' >/dev/null
expect "at most 8 apps (matches helper MAX_APPS)" "$(B settings-get | jq -c '[(.apps|length), (.apps|has("a6"))]')" '[8,false]'
B settings-set '{"apps":{"qbit":null,"a1":null,"a2":null,"a3":null,"a4":null,"a5":null}}' >/dev/null
expect "null patch removes custom apps" "$(B settings-get | jq -c '.apps|keys_unsorted')" '["heroic","steam"]'
B settings-set '{"apps":{"heroic":null}}' >/dev/null
expect "null on a preset only resets it" "$(B settings-get | jq -c '[(.apps|keys_unsorted), .apps.heroic.downMbit]')" '[["heroic","steam"],0]'
echo 'not json' > "$tmp/state/settings.json"
expect "corrupt file falls back to defaults" "$(B settings-get | jq -c .downMbit)" '0'
echo "== display / steps / history settings"
expect "new keys default" "$(B settings-get | jq -c '[.units,.barWidget,.steps,.keepDays]')" '["mbit","icon",[10,25,50,100],35]'
B settings-set '{"units":"mbyte","barWidget":"rate","steps":[50,5,20.7,5,10],"keepDays":7}' >/dev/null
expect "valid values kept (steps floored, deduped, sorted)" "$(B settings-get | jq -c '[.units,.barWidget,.steps,.keepDays]')" '["mbyte","rate",[5,10,20,50],7]'
B settings-set '{"units":"bits","barWidget":5,"steps":[0,-3,"x"],"keepDays":9999}' >/dev/null
expect "bad values fall back / clamp" "$(B settings-get | jq -c '[.units,.barWidget,.steps,.keepDays]')" '["mbit","icon",[10,25,50,100],365]'
B settings-set '{"steps":[1,2,3,4,5,6,7,8],"keepDays":0}' >/dev/null
expect "at most 6 steps, keepDays ≥ 1" "$(B settings-get | jq -c '[.steps,.keepDays]')" '[[1,2,3,4,5,6],1]'
B settings-set '{"steps":"10,25","keepDays":"x"}' >/dev/null
expect "wrong types → defaults" "$(B settings-get | jq -c '[.steps,.keepDays]')" '[[10,25,50,100],35]'

echo "== plan / app discovery"
cp /usr/bin/sleep "$tmp/yt-heroic"
systemd-run --user --quiet --collect --scope --unit=yt-unit-heroic "$tmp/yt-heroic" 300 >/dev/null 2>&1 &
for _ in $(seq 50); do pgrep -x -u "$uid" yt-heroic >/dev/null && break; sleep 0.1; done
cg=$(sed -n 's|^0::/||p' "/proc/$(pgrep -x -u "$uid" yt-heroic | head -1)/cgroup")
B settings-set '{"downMbit":0,"upMbit":0,"apps":{"heroic":{"downMbit":10,"upMbit":2,"gamesSafe":false}}}' >/dev/null
plan=$(B plan | head -1)
expect "plan passes heroic cgroup, mode all" "$plan" "apply --iface eth-test --down 0 --up 0 --app heroic:10000:2000:all:4:$cg "
expect "discovery reports heroic running" "$(B plan | tail -1 | jq -c '.[0] | [.running, (.cgroups|length)]')" '[true,1]'
B settings-set '{"apps":{"heroic":{"gamesSafe":true,"bulkMiB":8}}}' >/dev/null
expect_match "games-safe → bulk mode" "$(B plan | head -1)" "heroic:10000:2000:bulk:8:"
B settings-set '{"apps":{"heroic":{"bulkMiB":16},"steam":{"bulkMiB":16}}}' >/dev/null
expect_match "Settings › Games-safe threshold reaches the helper args" "$(B plan | head -1)" "heroic:10000:2000:bulk:16:"
B settings-set '{"apps":{"heroic":{"bulkMiB":8},"steam":{"bulkMiB":4}}}' >/dev/null
B settings-set '{"enabled":false}' >/dev/null
expect "master switch off → clear" "$(B plan | head -1)" "clear "
B settings-set '{"enabled":true,"apps":{"heroic":{"downMbit":0,"upMbit":0}}}' >/dev/null
expect "no caps → clear" "$(B plan | head -1)" "clear "
B settings-set '{"downMbit":25}' >/dev/null
expect "global only" "$(B plan | head -1)" "apply --iface eth-test --down 25000 --up 0 "

cp /usr/bin/sleep "$tmp/yt-torrent"
systemd-run --user --quiet --collect --scope --unit=yt-unit-torrent "$tmp/yt-torrent" 300 >/dev/null 2>&1 &
for _ in $(seq 50); do pgrep -x -u "$uid" yt-torrent >/dev/null && break; sleep 0.1; done
cgt=$(sed -n 's|^0::/||p' "/proc/$(pgrep -x -u "$uid" yt-torrent | head -1)/cgroup")
B settings-set '{"downMbit":0,"apps":{"torrent":{"label":"Torrent","procs":["yt-torrent"],"downMbit":12,"upMbit":1}}}' >/dev/null
expect "custom app gets its own --app slot" "$(B plan | head -1)" "apply --iface eth-test --down 0 --up 0 --app torrent:12000:1000:all:4:$cgt "
expect "custom app discovery" "$(B plan | tail -1 | jq -c '.[] | select(.key=="torrent") | [.running, .cgroups, .refused]')" "[true,[\"$cgt\"],[]]"
B settings-set '{"apps":{"torrent":{"gamesSafe":true}}}' >/dev/null
expect_match "custom app big-transfers-only → bulk" "$(B plan | head -1)" "torrent:12000:1000:bulk:4:"
systemctl --user stop yt-unit-torrent.scope >/dev/null 2>&1
B settings-set '{"downMbit":25,"apps":{"torrent":null}}' >/dev/null

echo "== tick with a fake sudo+helper (real helper in --dry-run validates the args)"
cat > "$tmp/fake-helper" <<FH
#!/usr/bin/env bash
echo "\$*" >> "$tmp/calls"
[[ -f "$tmp/fail" ]] && { echo "throttle-helper: boom" >&2; exit 2; }
THROTTLE_TEST=1 THROTTLE_TEST_UID=$uid bash "$helper" --dry-run "\$@" >/dev/null
FH
chmod +x "$tmp/fake-helper"
export THROTTLE_HELPER=$tmp/fake-helper THROTTLE_SUDO="" THROTTLE_LIVE_FIXTURE=$tmp/live
echo '{"ifb":true,"egress":false}' > "$tmp/live"
B settings-set '{"downMbit":25,"apps":{"heroic":{"downMbit":10}}}' >/dev/null
s1=$(B tick); s2=$(B tick)
expect "first tick applies" "$(jq -c '[.applied,.changed,.mode,.error]' <<<"$s1")" '[true,true,"apply",""]'
expect "second tick is a no-op" "$(jq -c '[.applied,.changed]' <<<"$s2")" '[true,false]'
expect "helper called once" "$(wc -l < "$tmp/calls")" "1"
B tick --force >/dev/null
expect "--force re-applies" "$(wc -l < "$tmp/calls")" "2"
echo '{"ifb":false,"egress":false}' > "$tmp/live"
B tick >/dev/null
expect "re-applies when shaping vanished (reboot/resume)" "$(wc -l < "$tmp/calls")" "3"
echo '{"ifb":true,"egress":false}' > "$tmp/live"
B settings-set '{"apps":{"heroic":{"downMbit":12}}}' >/dev/null
touch "$tmp/fail"
s3=$(B tick)
expect "helper failure is reported" "$(jq -c '[.applied,.error]' <<<"$s3")" '[false,"throttle-helper: boom"]'
rm -f "$tmp/fail"
s4=$(B tick)
expect "recovers on the next tick" "$(jq -c '[.applied,.error]' <<<"$s4")" '[true,""]'
systemctl --user stop yt-unit-heroic.scope >/dev/null 2>&1; sleep 0.3
B tick >/dev/null
expect_match "app exit changes the plan" "$(tail -1 "$tmp/calls")" "^apply --iface eth-test --down 25000 --up 0$"
unset THROTTLE_HELPER THROTTLE_SUDO THROTTLE_LIVE_FIXTURE
expect "missing helper → setup needed" "$(THROTTLE_HELPER=/nonexistent B tick | jq -r .helper)" "missing"

echo "== traffic (ss fixture)"
fx=$tmp/ss
w() { cat > "$fx" <<SS
0 0 10.0.0.2:5000 1.2.3.4:443 users:(("legendary",pid=11,fd=3)) uid:$uid ino:100 sk:1 cgroup:/user.slice/x <->
	 cubic bytes_sent:$2 bytes_acked:$2 bytes_received:$1 segs_out:1
0 0 10.0.0.2:5001 5.6.7.8:443 users:(("steamwebhelper",pid=12,fd=3)) uid:$uid ino:200 sk:2 cgroup:/user.slice/y <->
	 cubic bytes_acked:$4 bytes_received:$3 segs_out:1
0 0 10.0.0.2:5002 9.9.9.9:443 ino:300 sk:3 cgroup:/system.slice/tailscaled.service <->
	 cubic bytes_acked:10 bytes_received:10
SS
}
export THROTTLE_SS_FIXTURE=$fx
w 1000 100 5000 50; B traffic >/dev/null
w 1000 100 5000 50; sleep 1
w 1001000 100100 5000 50
t=$(B traffic)
expect "groups legendary under Heroic, ranks by rate" "$(jq -r '.apps[0].name' <<<"$t")" "Heroic"
hd=$(jq '.apps[0].down' <<<"$t"); iv=$(jq '.interval' <<<"$t")
expect_match "Heroic download ≈ 1 MB over the interval" "$(awk -v d="$hd" -v i="$iv" 'BEGIN{printf "%d", d*i}')" '^(99[0-9]{4}|100[0-9]{4})$'
expect "idle Steam socket reads 0" "$(jq -c '.apps[] | select(.name=="Steam") | [.down,.up,.conns]' <<<"$t")" '[0,0,1]'
expect "root daemons labelled by unit" "$(jq -r '[.apps[].name] | sort | join(",")' <<<"$t")" "Heroic,Steam,tailscaled"

w2() { cat > "$fx" <<SS
0 0 10.0.0.2:5003 1.2.3.4:443 users:(("yt-torrent",pid=13,fd=3)) uid:$uid ino:400 sk:4 cgroup:/user.slice/z <->
	 cubic bytes_acked:$2 bytes_received:$1
0 0 127.0.0.1:5004 127.0.0.1:9000 users:(("yt-torrent",pid=13,fd=4)) uid:$uid ino:500 sk:5 cgroup:/user.slice/z <->
	 cubic bytes_acked:$2 bytes_received:$1
0 0 10.0.0.2:5005 1.2.3.4:443 users:(("chrome",pid=14,fd=3)) uid:$uid ino:600 sk:6 cgroup:/user.slice/c <->
	 cubic bytes_acked:5 bytes_received:5
SS
}
B settings-set '{"apps":{"torrent":{"label":"Torrent","procs":["yt-torrent"]}}}' >/dev/null
rm -f "$tmp/run/ss.prev"; w2 100 10; B traffic >/dev/null; w2 200100 20010
t=$(B traffic)
expect "custom app labelled + keyed, loopback skipped" "$(jq -c '[.apps[] | [.name,.key,.proc,.own,.conns]]' <<<"$t")" '[["Torrent","torrent","yt-torrent",true,1],["chrome","","chrome",true,1]]'

echo "== stats (ss + /proc/net/dev fixtures)"
nd=$tmp/netdev; export THROTTLE_NETDEV_FIXTURE=$nd THROTTLE_TODAY=2026-10-25
S() { B stats-sample "$@"; }
rm -f "$tmp/run/stats.prev"
echo "eth-test 1000000 50000" > "$nd"; w2 100 10
expect "first sample is only a baseline" "$(S --print | jq -c '.days')" '[]'
echo "eth-test 1500000 80000" > "$nd"; w2 300100 20010
S --sync >/dev/null
expect "day totals: interface + per app" "$(B stats | jq -c '.days[0] | [.date,.rx,.tx,.apps]')" '["2026-10-25",500000,30000,[{"name":"Torrent","down":300000,"up":20000}]]'
expect "live copy is synced to disk" "$(jq -c '.days|keys' "$tmp/state/stats.json")" '["2026-10-25"]'
echo "eth-test 1600000 81000" > "$nd"; w2 350100 20510
S >/dev/null
expect "samples add up" "$(B stats | jq -c '.days[0] | [.rx,.tx,.apps[0].down,.apps[0].up]')" '[600000,31000,350000,20500]'
echo "eth-test 100 100" > "$nd"; w2 360100 20510
S >/dev/null
expect "counter reset (reboot/new iface) adds no interface bytes" "$(B stats | jq -c '.days[0] | [.rx,.apps[0].down]')" '[600000,360000]'
echo "eth-test 200 200" > "$nd"; THROTTLE_TODAY=2026-10-26 S >/dev/null
expect "new day starts its own bucket" "$(THROTTLE_TODAY=2026-10-26 B stats | jq -c '[.today, (.days|map(.date))]')" '["2026-10-26",["2026-10-25","2026-10-26"]]'
echo "eth-test 300 300" > "$nd"; THROTTLE_STATS_MAXGAP_S=0 S >/dev/null
expect "a long gap (shell was off) is not attributed" "$(B stats | jq -c '.days[-1].rx')" '100'
jq -c '.days["2026-09-01"] = {rx:1,tx:1,apps:{}} | .days["2026-09-20"] = {rx:2,tx:2,apps:{}}' "$tmp/run/stats.json" > "$tmp/s.json" && cp "$tmp/s.json" "$tmp/run/stats.json"
echo "eth-test 400 400" > "$nd"; S >/dev/null
expect "days older than keepDays (35) pruned" "$(B stats | jq -c '[.days[].date]')" '["2026-09-20","2026-10-25","2026-10-26"]'
B settings-set '{"keepDays":7}' >/dev/null
echo "eth-test 450 450" > "$nd"; S >/dev/null
expect "keepDays from Settings prunes harder" "$(B stats | jq -c '[.days[].date]')" '["2026-10-25","2026-10-26"]'
B settings-set '{"keepDays":35}' >/dev/null
jq -c '.days["2026-10-25"].apps = ([range(50)] | map({key: "p\(.)", value: [., 0]}) | from_entries)' "$tmp/run/stats.json" > "$tmp/s.json" && cp "$tmp/s.json" "$tmp/run/stats.json"
w2 999999 20510; S >/dev/null
expect "a day keeps at most 40 names" "$(jq -c '.days["2026-10-25"].apps | [length, .["Other apps"][0]]' "$tmp/run/stats.json")" '[40,66]'
S --sync >/dev/null; rm -f "$tmp/run/stats.json"
expect "restart reloads from disk" "$(B stats | jq -c '.days|length')" '2'
expect "stats-reset" "$(B stats-reset; B stats | jq -c .days)" '{"ok":true}
[]'
unset THROTTLE_NETDEV_FIXTURE THROTTLE_TODAY THROTTLE_SS_FIXTURE

echo "== helper argument validation (dry-run)"
H() { THROTTLE_TEST=1 THROTTLE_TEST_UID=$uid bash "$helper" --dry-run "$@" 2>&1; }
good="user.slice/user-$uid.slice/user@$uid.service/app.slice/app-Hyprland-heroic\\x2dx-1.scope"
for bad in \
  "apply --iface lo --down 1000 --up 0" \
  "apply --iface ifb-throttle --down 1000 --up 0" \
  "apply --iface eth0;reboot --down 1000 --up 0" \
  "apply --iface eth0 --down 10 --up 0" \
  "apply --iface eth0 --down 99999999 --up 0" \
  "apply --iface eth0 --down 1e3 --up 0" \
  "apply --iface eth0 --down 0 --up 0 --app Heroic:1000:0:all:4:$good" \
  "apply --iface eth0 --down 0 --up 0 --app heroic:1000:0:fast:4:$good" \
  "apply --iface eth0 --down 0 --up 0 --app heroic:1000:0:bulk:0:$good" \
  "apply --iface eth0 --down 0 --up 0 --app heroic:1000:0:all:4:user.slice/user-0.slice/user@0.service/x.scope" \
  "apply --iface eth0 --down 0 --up 0 --app heroic:1000:0:all:4:system.slice/sshd.service" \
  "apply --iface eth0 --down 0 --up 0 --app heroic:1000:0:all:4:user.slice/user-$uid.slice/user@$uid.service/../../../system.slice" \
  "apply --iface eth0 --down 0 --up 0 --app heroic:1000:0:all:4:user.slice/user-$uid.slice/user@$uid.service/a\"b" \
  "apply --iface eth0 --down 0 --up 0 --app heroic:1000:0:all:4:user.slice/user-$uid.slice/user@$uid.service/a\$(id)" \
  "apply --iface eth0 --down 0 --up 0 --bogus 1" \
  "apply --iface eth0 --down 0 --up 0$(for i in 1 2 3 4 5 6 7 8 9; do printf ' --app a%s:1000:0:all:4:%s' "$i" "$good"; done)" \
  "apply --iface eth0 --down 0 --up 0 --app google-chrome-stable:1000:0:all:4:$good" \
  "clear extra" \
  "rm -rf /"; do
  # shellcheck disable=SC2086
  out=$(H $bad); rc=$?
  if (( rc == 2 )); then ok "rejects: ${bad:0:80}"; else no "rejects: $bad" "rc=$rc $out"; fi
done
out=$(H apply --iface eth0 --down 50000 --up 20000 --app "heroic:10000:5000:bulk:4:$good"); rc=$?
expect "accepts a valid apply" "$rc" "0"
out8=$(H apply --iface eth0 --down 0 --up 0 $(for i in 1 2 3 4 5 6 7 8; do printf ' --app custom-%s:1000:0:all:4:%s' "$i" "$good"; done)); rc=$?
expect "accepts 8 apps incl. custom keys" "$rc $(grep -c 'socket cgroupv2' <<<"$out8")" "0 8"
expect_has "nft rule matches the escaped cgroup path" "$out" "socket cgroupv2 level 5 \"$good\" meta l4proto tcp ct bytes > 4194304"
expect_match "ingress redirect via ifb with ctinfo" "$out" "matchall action ctinfo cpmark 0x0f000000 action mirred egress redirect dev ifb-throttle"
expect_match "heroic class ceil 10 Mbit" "$out" "classid 1:11 htb rate 1000kbit ceil 10000kbit"
expect_match "conntrack accounting enabled for bulk mode" "$out" "echo 1 > /proc/sys/net/netfilter/nf_conntrack_acct"
expect "refuses real run without root" "$(bash "$helper" clear 2>&1; echo "rc=$?")" $'throttle-helper: must run as root (via sudo)\nrc=2'
expect "test overrides ignored under sudo" "$(SUDO_UID=$uid THROTTLE_TEST=1 THROTTLE_TEST_UID=4242 bash "$helper" --dry-run apply --iface eth0 --down 0 --up 0 --app "heroic:1000:0:all:4:user.slice/user-4242.slice/user@4242.service/x.scope" 2>&1; echo "rc=$?")" $'throttle-helper: bad cgroup path: user.slice/user-4242.slice/user@4242.service/x.scope\nrc=2'

echo "== vendored omarchy-yoyo-ui"
out=$(bash "$root/tools/sync-ui.sh" --check 2>&1); rc=$?
expect "vendor/yoyo-ui untouched (tools/sync-ui.sh --check)" "rc=$rc" "rc=0"
[[ $rc == 0 ]] || echo "$out"

echo
echo "passed $pass, failed $fail"
(( fail == 0 ))
