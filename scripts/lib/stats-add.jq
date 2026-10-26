# stats-add.jq — add one stats-sample to the daily totals (backend.sh stats_sample).
# Args: $day (YYYY-MM-DD), $cutoff (drop days before it), $d (ss-deltas.awk
# "bytes" output). A day keeps at most 40 names; the rest fold into "Other apps".
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
| .days |= with_entries(select(.key >= $cutoff))
