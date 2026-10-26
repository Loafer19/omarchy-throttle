# normalize($defaults): settings object → clean settings the helper accepts.
# Used by backend.sh (settings-get/-set); $defaults is defaults.js's CONFIG.
def normalize($defaults):
  def mbit: (tonumber? // 0) | floor | if . < 0 then 0 elif . > 10000 then 10000 else . end;
  def mib: (tonumber? // 4) | floor | if . < 1 then 1 elif . > 1024 then 1024 else . end;
  def app($d): {
    downMbit: ((.downMbit // $d.downMbit) | mbit),
    upMbit: ((.upMbit // $d.upMbit) | mbit),
    gamesSafe: (if (.gamesSafe | type) == "boolean" then .gamesSafe else $d.gamesSafe end),
    bulkMiB: ((.bulkMiB // $d.bulkMiB) | mib)
  };
  def dedupe: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
  def oneof($opts; $dflt): . as $v | if (type == "string") and any($opts[]; . == $v) then . else $dflt end;
  def steps($dflt): (if type == "array" then map(tonumber? // empty | floor | select(. >= 1 and . <= 10000)) | dedupe | sort | .[0:6] else [] end)
    | if length > 0 then . else $dflt end;
  def days($dflt): (tonumber? // $dflt) | floor | if . < 1 then 1 elif . > 365 then 365 else . end;
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
    units: ($s.units | oneof(["mbit", "mbyte"]; $d.units)),
    barWidget: ($s.barWidget | oneof(["icon", "dot", "rate"]; $d.barWidget)),
    steps: ($s.steps | steps($d.steps)),
    keepDays: (($s.keepDays // $d.keepDays) | days($d.keepDays)),
    apps: (($pre + $custom) | from_entries)
  };
