.pragma library
.import "defaults.js" as Defaults

var DEFAULTS = Defaults.CONFIG
var PRESETS = [0, 10, 25, 50, 100]
var MAX_MBIT = 10000

var APPS = [
  { key: "heroic", label: "Heroic", helpers: "legendary, gogdl, nile" },
  { key: "steam", label: "Steam", helpers: "steamwebhelper" }
]

function appLabel(key) {
  for (var i = 0; i < APPS.length; i++) if (APPS[i].key === key) return APPS[i].label
  return String(key)
}

function clampMbit(v) {
  var n = Math.floor(Number(v))
  if (!isFinite(n) || n < 0) return 0
  return n > MAX_MBIT ? MAX_MBIT : n
}

function isPreset(v) { return PRESETS.indexOf(clampMbit(v)) >= 0 }

function capLabel(v) {
  var n = clampMbit(v)
  return n === 0 ? "Off" : n + " Mbit/s"
}

// Chips for a rate row. "custom" is selected when the value is not a preset
// (or the row asked to show its custom field).
function rateChips() {
  var out = []
  for (var i = 0; i < PRESETS.length; i++)
    out.push({ key: String(PRESETS[i]), label: PRESETS[i] === 0 ? "Off" : String(PRESETS[i]) })
  out.push({ key: "custom", label: "Custom" })
  return out
}

function rateKey(v, customOpen) {
  if (customOpen || !isPreset(v)) return "custom"
  return String(clampMbit(v))
}

// Step through Off → 10 → 25 → 50 → 100 (custom values snap to the nearest step).
function stepPreset(v, delta) {
  var n = clampMbit(v), i, idx = -1
  for (i = 0; i < PRESETS.length; i++) if (PRESETS[i] === n) idx = i
  if (idx < 0) {
    idx = 0
    for (i = 0; i < PRESETS.length; i++) if (PRESETS[i] <= n) idx = i
    if (delta < 0 && PRESETS[idx] < n) delta = 0
  }
  idx = Math.max(0, Math.min(PRESETS.length - 1, idx + delta))
  return PRESETS[idx]
}

// bytes/s → "1.2 Mbit/s" (network people think in bits).
function formatRate(bytesPerSec) {
  var bits = Number(bytesPerSec || 0) * 8
  if (bits < 1000) return "0"
  if (bits < 1e6) return (bits / 1e3).toFixed(0) + " kbit/s"
  if (bits < 1e8) return (bits / 1e6).toFixed(1) + " Mbit/s"
  return (bits / 1e6).toFixed(0) + " Mbit/s"
}

function anyCap(cfg) {
  if (!cfg) return false
  if (clampMbit(cfg.downMbit) > 0 || clampMbit(cfg.upMbit) > 0) return true
  var apps = cfg.apps || {}
  for (var k in apps)
    if (clampMbit(apps[k].downMbit) > 0 || clampMbit(apps[k].upMbit) > 0) return true
  return false
}

function appStatus(status, key) {
  var list = status && status.apps ? status.apps : []
  for (var i = 0; i < list.length; i++) if (list[i].key === key) return list[i]
  return { key: key, running: false, cgroups: [], refused: [], shared: [] }
}

function appSubtitle(status, cfg, key) {
  var s = appStatus(status, key)
  var a = cfg && cfg.apps && cfg.apps[key] ? cfg.apps[key] : {}
  var capped = clampMbit(a.downMbit) > 0 || clampMbit(a.upMbit) > 0
  if (!s.running) return capped ? "Not running · applies when it starts" : "Not running"
  if (s.refused && s.refused.length && !(s.cgroups && s.cgroups.length))
    return "Can't limit: started outside an app scope (relaunch from the app menu)"
  var parts = []
  parts.push(capped ? (s.cgroups.length ? "Limited" : "Running") : "Running · no limit")
  if (s.shared && s.shared.length) parts.push("also caps: " + s.shared.slice(0, 3).join(", "))
  return parts.join(" · ")
}

// Rows of the Apps tab: per app a header plus down / up / games-safe rows.
function appRows(cfg, status) {
  var rows = []
  for (var i = 0; i < APPS.length; i++) {
    var app = APPS[i]
    var a = cfg && cfg.apps && cfg.apps[app.key] ? cfg.apps[app.key] : DEFAULTS.apps[app.key]
    rows.push({ kind: "header", app: app.key, title: app.label, subtitle: appSubtitle(status, cfg, app.key) })
    rows.push({ kind: "rate", app: app.key, field: "downMbit", title: "Download", value: clampMbit(a.downMbit) })
    rows.push({ kind: "rate", app: app.key, field: "upMbit", title: "Upload", value: clampMbit(a.upMbit) })
    rows.push({
      kind: "toggle", app: app.key, field: "gamesSafe", title: "Games-safe",
      subtitle: a.gamesSafe
        ? "Only TCP transfers over " + a.bulkMiB + " MiB — game UDP and small requests stay fast"
        : "Everything " + app.label + " and its children send is limited, games too",
      checked: !!a.gamesSafe
    })
  }
  return rows
}

function limitRows(cfg) {
  var c = cfg || DEFAULTS
  return [
    { kind: "rate", app: "", field: "downMbit", title: "Download", subtitle: "Whole connection", value: clampMbit(c.downMbit) },
    { kind: "rate", app: "", field: "upMbit", title: "Upload", subtitle: "Whole connection", value: clampMbit(c.upMbit) }
  ]
}

function patchFor(app, field, value) {
  var p = {}
  if (!app) { p[field] = value; return p }
  var inner = {}
  inner[field] = value
  p.apps = {}
  p.apps[app] = inner
  return p
}

// Deep-merge a patch into a cfg copy (optimistic UI update before the backend echoes).
function merged(cfg, patch) {
  var out = JSON.parse(JSON.stringify(cfg || DEFAULTS))
  function into(dst, src) {
    for (var k in src) {
      if (src[k] && typeof src[k] === "object" && !Array.isArray(src[k])) {
        if (!dst[k] || typeof dst[k] !== "object") dst[k] = {}
        into(dst[k], src[k])
      } else dst[k] = src[k]
    }
  }
  into(out, patch || {})
  return out
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
  for (var i = 0; i < APPS.length; i++) {
    var a = cfg.apps[APPS[i].key]
    if (a && (clampMbit(a.downMbit) > 0 || clampMbit(a.upMbit) > 0)) bits.push(APPS[i].label)
  }
  var where = status.iface ? " on " + status.iface : ""
  return (status.applied ? "Limiting" : "Applying") + where + " · " + bits.join(" · ")
}

function isLimiting(status, cfg) {
  return !!(status && status.helper === "installed" && status.applied && status.mode === "apply"
    && cfg && cfg.enabled !== false && anyCap(cfg))
}
