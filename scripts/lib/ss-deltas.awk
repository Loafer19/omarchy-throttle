# ss-deltas.awk — per-app TCP byte deltas between two `ss -tinpeH` samples.
#
# Input (stdin), as assembled by backend.sh ss_deltas:
#   #now NOW_NS IFACE RX TX        current time and interface counters
#   #prev NOW_NS IFACE RX TX       the previous sample's header (optional)
#   INO BYTES_IN BYTES_OUT         …one line per socket of the previous sample
#   #cur
#   <ss -tinpeH output>            the current sample
# Variables: mode=rates|bytes, maxgap (s), prevout (file for this sample's
# per-socket counters). ENVIRON: YT_LABELS ("proc<TAB>key<TAB>label" lines),
# THROTTLE_SS_FIXTURE (tests: don't read /proc).
# Output: mode=rates → traffic JSON; mode=bytes → "#iface<TAB>rx<TAB>tx<TAB>ok"
# then "name<TAB>down<TAB>up" lines (nothing when there is no usable baseline).
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
}
