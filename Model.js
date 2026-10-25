.pragma library
.import "defaults.js" as Defaults

var DEFAULTS = Defaults.CONFIG
var PRESETS = [0, 10, 25, 50, 100]
var MAX_MBIT = 10000

var MAX_APPS = DEFAULTS.limits.maxApps
var PROC_RE = /^[A-Za-z0-9][A-Za-z0-9 ._+:-]{0,14}$/
var KEY_RE = /^[a-z][a-z0-9-]{0,15}$/

// Apps in settings order (presets first): [{ key, label, preset, procs }]
function appList(cfg) {
  var apps = cfg && cfg.apps ? cfg.apps : DEFAULTS.apps
  var out = [], k
  for (k in DEFAULTS.presets) {
    var p = DEFAULTS.presets[k]
    out.push({ key: k, label: p.label, preset: true, procs: p.procs })
  }
  for (k in apps) {
    if (!apps[k] || DEFAULTS.presets[k]) continue
    out.push({ key: k, label: apps[k].label || k, preset: false, procs: apps[k].procs || [] })
  }
  return out
}

function appCfg(cfg, key) {
  var apps = cfg && cfg.apps ? cfg.apps : {}
  if (apps[key]) return apps[key]
  return DEFAULTS.apps[key] || DEFAULTS.custom
}

function appLabel(cfg, key) {
  var list = appList(cfg)
  for (var i = 0; i < list.length; i++) if (list[i].key === key) return list[i].label
  return String(key)
}

function isCapped(a) { return !!a && (clampMbit(a.downMbit) > 0 || clampMbit(a.upMbit) > 0) }

// Traffic / stats rows are named by label; is that app capped right now?
function labelCapped(cfg, label) {
  var list = appList(cfg)
  for (var i = 0; i < list.length; i++)
    if (list[i].label === label && isCapped(appCfg(cfg, list[i].key))) return true
  return false
}

function validProc(name) {
  var n = String(name || "")
  return PROC_RE.test(n) && DEFAULTS.denyProcs.indexOf(n) < 0
}

function knownProc(cfg, name) {
  var list = appList(cfg)
  for (var i = 0; i < list.length; i++) if (list[i].procs.indexOf(name) >= 0) return true
  return false
}

function canAdd(cfg) { return appList(cfg).length < MAX_APPS }

// "Google Chrome" / "qbittorrent" → a free settings key like "google-chrome".
function slugKey(name, cfg) {
  var base = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^[^a-z]+/, "").replace(/-+$/, "")
  if (!base) base = "app"
  base = base.slice(0, 14).replace(/-+$/, "")
  var taken = {}, list = appList(cfg)
  for (var i = 0; i < list.length; i++) taken[list[i].key] = true
  if (!taken[base]) return base
  for (var n = 2; n < 100; n++) if (!taken[base + "-" + n]) return base + "-" + n
  return ""
}

function prettyLabel(proc) {
  var s = String(proc || "")
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s
}

// Patch that adds a custom app for one process name, or null if not allowed.
function addPatch(cfg, proc) {
  var name = String(proc || "").trim()
  if (!validProc(name) || knownProc(cfg, name) || !canAdd(cfg)) return null
  var key = slugKey(name, cfg)
  if (!KEY_RE.test(key)) return null
  var p = { apps: {} }
  p.apps[key] = { label: prettyLabel(name), procs: [name], downMbit: 0, upMbit: 0,
    gamesSafe: DEFAULTS.custom.gamesSafe, bulkMiB: DEFAULTS.custom.bulkMiB, preset: false }
  return p
}

function removePatch(cfg, key) {
  if (!key || DEFAULTS.presets[key]) return null
  var p = { apps: {} }
  p.apps[key] = null
  return p
}

// Programs with open connections that aren't an app yet: one-click "Add".
function candidates(traffic, cfg) {
  var list = traffic && traffic.apps ? traffic.apps : [], out = []
  for (var i = 0; i < list.length && out.length < 6; i++) {
    var t = list[i]
    if (!t.own || t.key || !validProc(t.proc) || knownProc(cfg, t.proc)) continue
    out.push({ proc: t.proc, down: t.down || 0, up: t.up || 0, conns: t.conns || 0 })
  }
  return out
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
  var capped = isCapped(appCfg(cfg, key))
  if (!s.running) return capped ? "Not running · applies when it starts" : "Not running"
  if (s.refused && s.refused.length && !(s.cgroups && s.cgroups.length))
    return "Can't limit: started outside an app scope (relaunch from the app menu)"
  var parts = []
  parts.push(capped ? (s.cgroups.length ? "Limited" : "Running") : "Running · no limit")
  if (s.shared && s.shared.length) parts.push("also caps: " + s.shared.slice(0, 3).join(", "))
  return parts.join(" · ")
}

// Rows of the Apps tab: per app a header plus down / up / games-safe rows,
// then "Add an app" (programs seen on the network, and a name field).
function appRows(cfg, status, traffic) {
  var rows = [], list = appList(cfg)
  for (var i = 0; i < list.length; i++) {
    var app = list[i]
    var a = appCfg(cfg, app.key)
    var procs = app.preset ? "" : " · " + app.procs.join(", ")
    rows.push({ kind: "header", app: app.key, title: app.label, removable: !app.preset,
      subtitle: appSubtitle(status, cfg, app.key) + procs })
    rows.push({ kind: "rate", app: app.key, field: "downMbit", title: "Download", value: clampMbit(a.downMbit) })
    rows.push({ kind: "rate", app: app.key, field: "upMbit", title: "Upload", value: clampMbit(a.upMbit) })
    rows.push({
      kind: "toggle", app: app.key, field: "gamesSafe", title: app.preset ? "Games-safe" : "Big transfers only",
      subtitle: a.gamesSafe
        ? "Only TCP transfers over " + a.bulkMiB + " MiB — " + (app.preset ? "game UDP and small requests stay fast" : "calls, streams and browsing stay fast")
        : "Everything " + app.label + " and its children send is limited" + (app.preset ? ", games too" : ""),
      checked: !!a.gamesSafe
    })
  }
  if (!canAdd(cfg)) {
    rows.push({ kind: "note", title: "Up to " + MAX_APPS + " apps — remove one to add another" })
    return rows
  }
  rows.push({ kind: "section", title: "Add an app", subtitle: "Programs with open connections right now, or type a process name" })
  var c = candidates(traffic, cfg)
  for (var j = 0; j < c.length; j++)
    rows.push({ kind: "candidate", proc: c[j].proc, title: c[j].proc, down: c[j].down, up: c[j].up, conns: c[j].conns })
  rows.push({ kind: "addfield", title: "Process name" })
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

// Deep-merge a patch into a cfg copy (optimistic UI update before the backend
// echoes). A null removes the key — unless keepNulls (merging patches that are
// still to be sent, where the null is the instruction).
function merged(cfg, patch, keepNulls) {
  var out = JSON.parse(JSON.stringify(cfg || DEFAULTS))
  function into(dst, src) {
    for (var k in src) {
      if (src[k] === null && !keepNulls) delete dst[k]
      else if (src[k] && typeof src[k] === "object" && !Array.isArray(src[k])) {
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
  var list = appList(cfg)
  for (var i = 0; i < list.length; i++)
    if (isCapped(appCfg(cfg, list[i].key))) bits.push(list[i].label)
  var where = status.iface ? " on " + status.iface : ""
  return (status.applied ? "Limiting" : "Applying") + where + " · " + bits.join(" · ")
}

function isLimiting(status, cfg) {
  return !!(status && status.helper === "installed" && status.applied && status.mode === "apply"
    && cfg && cfg.enabled !== false && anyCap(cfg))
}

// ---------------------------------------------------------------- stats ---
var RANGES = [
  { key: "today", label: "Today", days: 1, chart: 7 },
  { key: "week", label: "7 days", days: 7, chart: 7 },
  { key: "month", label: "30 days", days: 30, chart: 30 }
]

function formatBytes(n) {
  var b = Number(n || 0)
  if (b < 1024) return b.toFixed(0) + " B"
  if (b < 1048576) return (b / 1024).toFixed(0) + " KiB"
  if (b < 1073741824) return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + " MiB"
  return (b / 1073741824).toFixed(b < 10737418240 ? 2 : 1) + " GiB"
}

// "2026-10-25" ± n days, no time zones involved.
function shiftDate(iso, n) {
  var p = String(iso).split("-")
  var d = new Date(Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2]) + n))
  function z(v) { return v < 10 ? "0" + v : String(v) }
  return d.getUTCFullYear() + "-" + z(d.getUTCMonth() + 1) + "-" + z(d.getUTCDate())
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
function dayLabel(iso, short) {
  var p = String(iso).split("-")
  var d = new Date(Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2])))
  return short ? String(d.getUTCDate()) : WEEKDAYS[d.getUTCDay()]
}

function rangeOf(key) {
  for (var i = 0; i < RANGES.length; i++) if (RANGES[i].key === key) return RANGES[i]
  return RANGES[0]
}

// Totals for the range, per-app rows (+ "Other / UDP" = interface − TCP rows),
// and per-day bars for the chart.
function statsSummary(stats, rangeKey) {
  var r = rangeOf(rangeKey)
  var today = stats && stats.today ? stats.today : shiftDate("1970-01-01", 0)
  var byDate = {}, days = stats && stats.days ? stats.days : []
  for (var i = 0; i < days.length; i++) byDate[days[i].date] = days[i]
  var from = shiftDate(today, -(r.days - 1))
  var total = { down: 0, up: 0 }, apps = {}, order = []
  for (var d = 0; d < r.days; d++) {
    var day = byDate[shiftDate(from, d)]
    if (!day) continue
    total.down += day.rx || 0; total.up += day.tx || 0
    for (var j = 0; j < day.apps.length; j++) {
      var a = day.apps[j]
      if (!apps[a.name]) { apps[a.name] = { name: a.name, down: 0, up: 0 }; order.push(a.name) }
      apps[a.name].down += a.down || 0; apps[a.name].up += a.up || 0
    }
  }
  var rows = [], sumD = 0, sumU = 0
  for (var k = 0; k < order.length; k++) { rows.push(apps[order[k]]); sumD += apps[order[k]].down; sumU += apps[order[k]].up }
  rows.sort(function(x, y) { return (y.down + y.up) - (x.down + x.up) || (x.name < y.name ? -1 : 1) })
  var other = { name: "Other / UDP", down: Math.max(0, total.down - sumD), up: Math.max(0, total.up - sumU), other: true }
  if (other.down + other.up > 0) rows.push(other)
  var bars = [], peak = 1
  var chartFrom = shiftDate(today, -(r.chart - 1))
  for (var c = 0; c < r.chart; c++) {
    var date = shiftDate(chartFrom, c), dd = byDate[date]
    var bar = { date: date, label: dayLabel(date, r.chart > 7), down: dd ? dd.rx || 0 : 0, up: dd ? dd.tx || 0 : 0,
      inRange: date >= from, today: date === today }
    peak = Math.max(peak, bar.down + bar.up)
    bars.push(bar)
  }
  return { range: r.key, total: total, apps: rows, bars: bars, peak: peak }
}

function statsRows(summary) {
  var rows = [{ kind: "range" }, { kind: "chart" }]
  for (var i = 0; i < summary.apps.length; i++) {
    var a = summary.apps[i]
    rows.push({ kind: "stat", name: a.name, down: a.down, up: a.up, other: !!a.other })
  }
  return rows
}
