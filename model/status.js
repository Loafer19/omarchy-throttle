.pragma library
.import "../defaults.js" as Defaults
.import "format.js" as Format
.import "apps.js" as Apps

// Status line, limiting state and the bar widget's tooltip / dot.
var DEFAULTS = Defaults.CONFIG
var appList = Apps.appList
var appCfg = Apps.appCfg
var isCapped = Apps.isCapped
var clampMbit = Format.clampMbit
var formatRate = Format.formatRate
var capBytes = Format.capBytes
var anyCap = Apps.anyCap
var liveOf = Apps.liveOf

// Capped apps (and the whole-connection cap) with their live rate.
function capUse(cfg, traffic) {
  var out = [], list = appList(cfg), c = cfg || DEFAULTS
  for (var i = 0; i < list.length; i++) {
    var a = appCfg(cfg, list[i].key)
    if (!isCapped(a)) continue
    var live = liveOf(traffic, list[i].key)
    out.push({ label: list[i].label, down: live.down, up: live.up, capDown: clampMbit(a.downMbit), capUp: clampMbit(a.upMbit), seen: live.seen })
  }
  if (isCapped(c)) {
    var t = traffic && traffic.iface ? traffic.iface : { down: 0, up: 0 }
    out.push({ label: "Whole connection", down: t.down || 0, up: t.up || 0, capDown: clampMbit(c.downMbit), capUp: clampMbit(c.upMbit), seen: !!(traffic && traffic.iface) })
  }
  return out
}

// A cap is "biting" when its traffic runs at 90 % of the cap or more.
function biting(cfg, traffic) {
  var u = capUse(cfg, traffic)
  for (var i = 0; i < u.length; i++) {
    if (u[i].capDown > 0 && u[i].down >= capBytes(u[i].capDown) * 0.9) return true
    if (u[i].capUp > 0 && u[i].up >= capBytes(u[i].capUp) * 0.9) return true
  }
  return false
}

function tooltipText(cfg, status, traffic, limiting, units) {
  if (!status) return "Throttle"
  if (status.helper !== "installed") return "Throttle · one-time setup needed"
  if (status.error) return "Throttle · " + status.error
  if (cfg && cfg.enabled === false) return "Throttle paused · right-click to resume"
  if (!anyCap(cfg)) return "Throttle · no limits"
  var lines = [(limiting ? "Throttle on" : "Throttle applying") + (status.iface ? " · " + status.iface : "")]
  var u = capUse(cfg, traffic)
  for (var i = 0; i < u.length && i < 6; i++) {
    var x = u[i], parts = []
    if (x.capDown > 0) parts.push("↓ " + (x.seen ? formatRate(x.down, units) + " / " : "") + x.capDown + " Mbit/s")
    if (x.capUp > 0) parts.push("↑ " + (x.seen ? formatRate(x.up, units) + " / " : "") + x.capUp + " Mbit/s")
    lines.push(x.label + "  " + parts.join("  "))
  }
  lines.push("Right-click to pause")
  return lines.join("\n")
}

function statusLine(status, cfg) {
  if (!status) return "Checking…"
  if (status.helper !== "installed") return "One-time setup needed"
  if (status.error) return "Error: " + status.error
  if (!cfg || cfg.enabled === false) return "Paused — nothing is limited"
  if (!anyCap(cfg)) return "No limits set"
  var bits = []
  if (clampMbit(cfg.downMbit) > 0) bits.push("↓ " + cfg.downMbit + " Mbit/s")
  if (clampMbit(cfg.upMbit) > 0) bits.push("↑ " + cfg.upMbit + " Mbit/s")
  var names = appList(cfg).filter(function(app) { return isCapped(appCfg(cfg, app.key)) })
    .map(function(app) { return app.label })
  bits = bits.concat(names.length > 3 ? names.slice(0, 2).concat(["+" + (names.length - 2) + " apps"]) : names)
  var where = status.iface ? " on " + status.iface : ""
  return (status.applied ? "Limiting" : "Applying") + where + " · " + bits.join(" · ")
}

function isLimiting(status, cfg) {
  return !!(status && status.helper === "installed" && status.applied && status.mode === "apply"
    && cfg && cfg.enabled !== false && anyCap(cfg))
}
