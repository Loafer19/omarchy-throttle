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

// The kernel keeps 15 characters of a process name ("telegram-deskto");
// a longer typed or resolved name is matched by its first 15 and kept as label.
function procOf(name) { return String(name || "").trim().slice(0, 15) }
function validName(name) {
  var n = String(name || "").trim()
  return n.length <= 32 && /^[A-Za-z0-9][A-Za-z0-9 ._+:-]*$/.test(n) && validProc(procOf(n))
}

// Patch that adds a custom app for one process name, or null if not allowed.
function addPatch(cfg, nameIn, labelIn) {
  var full = String(labelIn || nameIn || "").trim()
  var name = procOf(nameIn)
  if (!validName(nameIn) || knownProc(cfg, name) || !canAdd(cfg)) return null
  var key = slugKey(full, cfg)
  if (!KEY_RE.test(key)) return null
  var p = { apps: {} }
  p.apps[key] = { label: prettyLabel(full.slice(0, 32)), procs: [name], downMbit: 0, upMbit: 0,
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
    out.push({ proc: t.proc, full: t.full || t.proc, down: t.down || 0, up: t.up || 0, conns: t.conns || 0 })
  }
  return out
}

function clampMbit(v) {
  var n = Math.floor(Number(v))
  if (!isFinite(n) || n < 0) return 0
  return n > MAX_MBIT ? MAX_MBIT : n
}

// Rate chips: Off plus the user's steps (Settings › Preset steps).
var STEP_SETS = [[10, 25, 50, 100], [5, 10, 20, 50], [25, 50, 100, 250]]

function stepsOf(cfg) {
  var s = cfg && Array.isArray(cfg.steps) ? cfg.steps : DEFAULTS.steps
  var out = [0]
  for (var i = 0; i < s.length && out.length < 7; i++) {
    var n = clampMbit(s[i])
    if (n > 0 && out.indexOf(n) < 0) out.push(n)
  }
  out.sort(function(a, b) { return a - b })
  return out.length > 1 ? out : PRESETS
}

function isPreset(v, steps) { return (steps || PRESETS).indexOf(clampMbit(v)) >= 0 }

function capLabel(v) {
  var n = clampMbit(v)
  return n === 0 ? "Off" : n + " Mbit/s"
}

// "10 Mbit/s ≈ 1.2 MB/s": caps are set in Mbit/s, the MB/s hint is for
// people who read download speeds off Steam or a browser.
function mbyteOf(mbit) {
  var b = clampMbit(mbit) / 8
  return (b < 10 ? b.toFixed(1) : b.toFixed(0)) + " MB/s"
}
function capDetail(v) {
  var n = clampMbit(v)
  return n === 0 ? "Off · no cap" : n + " Mbit/s ≈ " + mbyteOf(n)
}

// Chips for a rate row. "custom" is selected when the value is not a step
// (or the row asked to show its custom field).
function rateChips(steps) {
  var s = steps || PRESETS, out = []
  for (var i = 0; i < s.length; i++)
    out.push({ key: String(s[i]), label: s[i] === 0 ? "Off" : String(s[i]) })
  out.push({ key: "custom", label: "Custom" })
  return out
}

function rateKey(v, customOpen, steps) {
  if (customOpen || !isPreset(v, steps)) return "custom"
  return String(clampMbit(v))
}

// Step through Off → 10 → 25 → 50 → 100 (custom values snap to the nearest step).
function stepPreset(v, delta, steps) {
  var s = steps || PRESETS
  var n = clampMbit(v), i, idx = -1
  for (i = 0; i < s.length; i++) if (s[i] === n) idx = i
  if (idx < 0) {
    idx = 0
    for (i = 0; i < s.length; i++) if (s[i] <= n) idx = i
    if (delta < 0 && s[idx] < n) delta = 0
  }
  idx = Math.max(0, Math.min(s.length - 1, idx + delta))
  return s[idx]
}

// bytes/s → "1.2 Mbit/s" (network people think in bits) or, with units
// "mbyte", "150 kB/s" / "1.2 MB/s".
function formatRate(bytesPerSec, units) {
  var b = Number(bytesPerSec || 0)
  if (units === "mbyte") {
    if (b < 1000) return "0"
    if (b < 1e6) return (b / 1e3).toFixed(0) + " kB/s"
    if (b < 1e8) return (b / 1e6).toFixed(1) + " MB/s"
    return (b / 1e6).toFixed(0) + " MB/s"
  }
  var bits = b * 8
  if (bits < 1000) return "0"
  if (bits < 1e6) return (bits / 1e3).toFixed(0) + " kbit/s"
  if (bits < 1e8) return (bits / 1e6).toFixed(1) + " Mbit/s"
  return (bits / 1e6).toFixed(0) + " Mbit/s"
}

// Bar label: "9.9M" / "850k" (bits) or "1.2MB" / "85kB".
function shortRate(bytesPerSec, units) {
  var b = Number(bytesPerSec || 0), mb = units === "mbyte", v = mb ? b : b * 8
  var unit = mb ? "B" : ""
  if (v < 1000) return "0"
  if (v < 1e6) return (v / 1e3).toFixed(0) + "k" + unit
  if (v < 1e7) return (v / 1e6).toFixed(1) + "M" + unit
  return (v / 1e6).toFixed(0) + "M" + unit
}

// Mbit/s cap → bytes/s, for comparing with live rates.
function capBytes(mbit) { return clampMbit(mbit) * 125000 }

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

// ------------------------------------------------------------ views ---
// Two-level tabs: Limits (Apps / Connection / + Add), Traffic (Live / Today /
// 7 days / 30 days) and Settings. Every view is a flat list of rows, one
// ListView in the panel; rows with a "kind" the cursor can't land on are
// listed in UNSELECTABLE.
var TABS = [
  { key: "limits", label: "Limits" },
  { key: "traffic", label: "Traffic" },
  { key: "settings", label: "Settings" }
]
var SUBTABS = {
  limits: [{ key: "apps", label: "Apps" }, { key: "connection", label: "Connection" }, { key: "add", label: "+ Add" }],
  traffic: [{ key: "live", label: "Live" }, { key: "today", label: "Today" }, { key: "week", label: "7 days" }, { key: "month", label: "30 days" }],
  settings: []
}
var UNSELECTABLE = ["section", "note", "empty", "total", "livechart", "daychart"]

function subtabsOf(tab) { return SUBTABS[tab] || [] }

function selectableRow(r) {
  if (!r || UNSELECTABLE.indexOf(r.kind) >= 0) return false
  if (r.kind === "hero") return r.removable === true
  return true
}

// Live rate of a configured app: traffic rows carry the app key.
function liveOf(traffic, key) {
  var list = traffic && traffic.apps ? traffic.apps : [], out = { down: 0, up: 0, seen: false }
  for (var i = 0; i < list.length; i++)
    if (list[i].key === key) { out.down += list[i].down || 0; out.up += list[i].up || 0; out.seen = true }
  return out
}

// Settings key of the app a traffic / stats row is named after (label), or "".
function keyOfLabel(cfg, label) {
  var list = appList(cfg)
  for (var i = 0; i < list.length; i++) if (list[i].label === label) return list[i].key
  return ""
}

// "limited" (accent dot) · "running" · "idle" (not running) · "refused".
function appState(status, cfg, key, limiting) {
  var s = appStatus(status, key)
  if (!s.running) return "idle"
  if (s.refused && s.refused.length && !(s.cgroups && s.cgroups.length)) return "refused"
  if (limiting && s.cgroups && s.cgroups.length && isCapped(appCfg(cfg, key))) return "limited"
  return "running"
}

// Limits › Apps: one compact row per app, then the whole-connection row.
function appListRows(cfg, status, traffic, limiting, units) {
  var rows = [], list = appList(cfg)
  for (var i = 0; i < list.length; i++) {
    var app = list[i], a = appCfg(cfg, app.key)
    var sub = pausedWording(cfg, appSubtitle(status, cfg, app.key))
    if (a.gamesSafe && isCapped(a) && sub.indexOf("Can't") !== 0) sub += " · games-safe"
    var live = liveOf(traffic, app.key)
    if (live.down >= 125) sub += " · ↓ " + formatRate(live.down, units) + " now"
    rows.push({ kind: "app", app: app.key, title: app.label, subtitle: sub,
      down: clampMbit(a.downMbit), up: clampMbit(a.upMbit), state: appState(status, cfg, app.key, limiting) })
  }
  var c = cfg || DEFAULTS
  rows.push({ kind: "section", title: "Whole connection" })
  rows.push({ kind: "link", target: "connection", title: "All traffic",
    subtitle: "Every app on " + (status && status.iface ? status.iface : "this connection") + " together",
    down: clampMbit(c.downMbit), up: clampMbit(c.upMbit) })
  return rows
}

// While paused nothing is shaped, so "Limited" would be a lie.
function pausedWording(cfg, sub) {
  return cfg && cfg.enabled === false && sub.indexOf("Limited") === 0 ? "Paused" + sub.slice(7) : sub
}

function gamesSafeSubtitle(a, label) {
  return a.gamesSafe
    ? "Only TCP transfers over " + a.bulkMiB + " MiB are capped — game UDP, calls and small requests stay fast"
    : "Everything " + label + " and its children send is capped"
}

// Limits › Apps › <app>: breadcrumb, hero, the two caps and Games-safe.
function detailRows(cfg, status, traffic, key, limiting, units) {
  var app = null, list = appList(cfg)
  for (var i = 0; i < list.length; i++) if (list[i].key === key) app = list[i]
  if (!app) return []
  var a = appCfg(cfg, key), live = liveOf(traffic, key)
  var trailing = ""
  if (live.seen && clampMbit(a.downMbit) > 0) trailing = "↓ " + formatRate(live.down, units).replace(/ Mbit\/s$/, "") + " / " + clampMbit(a.downMbit) + " Mbit/s"
  else if (live.seen) trailing = "↓ " + formatRate(live.down, units)
  return [
    { kind: "crumb", title: app.label },
    { kind: "hero", app: key, title: app.label, removable: !app.preset, state: appState(status, cfg, key, limiting),
      subtitle: pausedWording(cfg, appSubtitle(status, cfg, key)) + " · " + app.procs.join(", "), trailing: trailing },
    { kind: "rate", app: key, field: "downMbit", title: "Download", value: clampMbit(a.downMbit) },
    { kind: "rate", app: key, field: "upMbit", title: "Upload", value: clampMbit(a.upMbit) },
    { kind: "toggle", app: key, field: "gamesSafe", title: "Games-safe", subtitle: gamesSafeSubtitle(a, app.label), checked: !!a.gamesSafe }
  ]
}

// Limits › Connection: the whole-interface caps.
function connectionRows(cfg, status) {
  var c = cfg || DEFAULTS
  var where = status && status.iface ? status.iface : "the default interface"
  return [
    { kind: "rate", app: "", field: "downMbit", title: "Download", value: clampMbit(c.downMbit) },
    { kind: "rate", app: "", field: "upMbit", title: "Upload", value: clampMbit(c.upMbit) },
    { kind: "note", title: "Caps everything on " + where + ", on top of any per-app caps." }
  ]
}

// Limits › + Add: programs online now, or a process name.
function addRows(cfg, traffic) {
  if (!canAdd(cfg)) return [{ kind: "empty", title: "Up to " + MAX_APPS + " apps", subtitle: "Remove one in Apps to add another" }]
  var rows = [{ kind: "section", title: "Online now", caption: "programs with open connections" }]
  var c = candidates(traffic, cfg)
  for (var j = 0; j < c.length; j++)
    rows.push({ kind: "candidate", proc: c[j].proc, title: c[j].full, down: c[j].down, up: c[j].up, conns: c[j].conns })
  if (c.length === 0)
    rows.push({ kind: "note", title: traffic ? "Nothing new online right now." : "Measuring…" })
  rows.push({ kind: "section", title: "By name", caption: "as in ps -o comm" })
  rows.push({ kind: "addfield", title: "Process name" })
  return rows
}

// Traffic › Live: totals, the per-app chart, then one row per program.
function liveRows(cfg, traffic, history) {
  var t = traffic && traffic.iface ? traffic.iface : null
  var series = liveSeries(history, 4, (cfg || DEFAULTS).units)
  var rows = [
    { kind: "total", down: t ? t.down : 0, up: t ? t.up : 0, measuring: !t,
      caption: series.peak > 0 ? "peak " + formatRate(series.peak, (cfg || DEFAULTS).units) + " · " + Math.round(series.span) + " s" : "" },
    { kind: "livechart" },
    { kind: "section", title: "Apps", caption: "TCP per app · UDP is in Other" }
  ]
  var list = traffic && traffic.apps ? traffic.apps : []
  for (var i = 0; i < list.length; i++) {
    var x = list[i], a = x.key ? appCfg(cfg, x.key) : null
    rows.push({ kind: "traffic", name: (x.key ? x.name : (x.full || x.name)) || "", key: x.key || "", proc: x.proc || "",
      down: x.down || 0, up: x.up || 0, conns: x.conns || 0,
      capDown: a ? clampMbit(a.downMbit) : 0, capUp: a ? clampMbit(a.upMbit) : 0,
      addable: !x.key && !!x.own && validProc(x.proc) && !knownProc(cfg, x.proc) && canAdd(cfg) })
  }
  if (list.length === 0) rows.push({ kind: "empty", title: traffic ? "No open TCP connections" : "Measuring…",
    subtitle: traffic ? "Programs show up here once they talk to the network" : "" })
  return rows
}

// Traffic › Today / 7 days / 30 days.
function historyRows(cfg, summary, loaded) {
  var rows = [
    { kind: "total", bytes: true, down: summary.total.down, up: summary.total.up, caption: "peak " + formatBytes(summary.peak) + "/day" },
    { kind: "daychart" },
    { kind: "section", title: "By app", caption: "TCP payload · Other is UDP and the rest" }
  ]
  for (var i = 0; i < summary.apps.length; i++) {
    var a = summary.apps[i], key = a.other ? "" : keyOfLabel(cfg, a.name), c = key ? appCfg(cfg, key) : null
    rows.push({ kind: "stat", name: a.name, key: key, down: a.down, up: a.up, other: !!a.other,
      capDown: c ? clampMbit(c.downMbit) : 0, capUp: c ? clampMbit(c.upMbit) : 0 })
  }
  if (summary.apps.length === 0) rows.push({ kind: "empty", title: loaded ? "Nothing counted in this range yet" : "Loading…",
    subtitle: loaded ? "History starts when the shell does; it is kept on this machine only" : "" })
  return rows
}

// -------------------------------------------------------- settings ---
var UNIT_CHOICES = [{ key: "mbit", label: "Mbit/s" }, { key: "mbyte", label: "MB/s" }]
var WIDGET_CHOICES = [{ key: "icon", label: "Icon" }, { key: "dot", label: "Icon + dot" }, { key: "rate", label: "Icon + rate" }]
var BULK_CHOICES = [2, 4, 8, 16]
var KEEP_CHOICES = [7, 35, 90]

function stepsKey(list) { return list.join(",") }
function bulkOf(cfg) { var l = appList(cfg); return l.length ? appCfg(cfg, l[0].key).bulkMiB : DEFAULTS.custom.bulkMiB }

function settingsRows(cfg, status, installed) {
  var c = cfg || DEFAULTS, steps = stepsOf(c).slice(1)
  var stepOpts = [], i
  for (i = 0; i < STEP_SETS.length; i++) stepOpts.push({ key: stepsKey(STEP_SETS[i]), label: STEP_SETS[i].join("/") })
  if (stepOpts.map(function(o) { return o.key }).indexOf(stepsKey(steps)) < 0)
    stepOpts.push({ key: stepsKey(steps), label: steps.join("/") })
  var bulkOpts = [], keepOpts = []
  for (i = 0; i < BULK_CHOICES.length; i++)
    bulkOpts.push({ key: String(BULK_CHOICES[i]), label: BULK_CHOICES[i] + (i === BULK_CHOICES.length - 1 ? " MiB" : "") })
  for (i = 0; i < KEEP_CHOICES.length; i++)
    keepOpts.push({ key: String(KEEP_CHOICES[i]), label: KEEP_CHOICES[i] + (i === KEEP_CHOICES.length - 1 ? " days" : "") })
  var keep = c.keepDays || DEFAULTS.keepDays
  if (KEEP_CHOICES.indexOf(keep) < 0) keepOpts.push({ key: String(keep), label: keep + " days" })
  var iface = status && status.iface ? status.iface : "auto"
  return [
    { kind: "section", title: "Display" },
    { kind: "choice", setting: "units", title: "Live rates in", subtitle: "Caps are always set in Mbit/s", options: UNIT_CHOICES, value: c.units || "mbit" },
    { kind: "choice", setting: "barWidget", title: "Bar widget", subtitle: "Dot: a cap is maxed out · Rate: live ↓", options: WIDGET_CHOICES, value: c.barWidget || "icon" },
    { kind: "section", title: "Limits" },
    { kind: "choice", setting: "steps", title: "Preset steps", subtitle: "Mbit/s chips next to Off · Custom", options: stepOpts, value: stepsKey(steps) },
    { kind: "choice", setting: "bulkMiB", title: "Games-safe threshold", subtitle: "Transfers bigger than this get capped", options: bulkOpts, value: String(bulkOf(c)) },
    { kind: "section", title: "History" },
    { kind: "choice", setting: "keepDays", title: "Keep history", subtitle: "Per-app totals, stored on this machine", options: keepOpts, value: String(keep) },
    { kind: "action", action: "clear-history", title: "Clear history", subtitle: "Forget every counted day", chip: "Clear", confirm: true },
    { kind: "section", title: "Helper" },
    installed
      ? { kind: "action", action: "copy-uninstall", title: "Helper installed", subtitle: "tc + nftables via a root helper · " + iface, chip: "Copy uninstall" }
      : { kind: "action", action: "copy-install", title: "Helper not installed", subtitle: "Shaping needs a one-time sudo install", chip: "Copy install" }
  ]
}

// Patch for a Settings choice; the Games-safe threshold goes to every app.
function settingPatch(cfg, setting, key) {
  if (setting === "units" || setting === "barWidget") { var p = {}; p[setting] = key; return p }
  if (setting === "steps") return { steps: String(key).split(",").map(Number) }
  if (setting === "keepDays") return { keepDays: Number(key) }
  if (setting === "bulkMiB") {
    var out = { apps: {} }, list = appList(cfg)
    for (var i = 0; i < list.length; i++) out.apps[list[i].key] = { bulkMiB: Number(key) }
    return out
  }
  return null
}

// Next / previous option of a choice row (wraps for Enter, clamps for h/l).
function stepChoice(row, delta, wrap) {
  var o = row.options || [], i = 0
  for (var k = 0; k < o.length; k++) if (String(o[k].key) === String(row.value)) i = k
  i += delta
  if (wrap) i = (i + o.length) % o.length
  else i = Math.max(0, Math.min(o.length - 1, i))
  return o.length ? String(o[i].key) : ""
}

// ------------------------------------------------------- live chart ---
var LIVE_SAMPLES = 60

// Ring buffer of traffic samples (one per 1.5 s → 90 s). A gap (panel was
// closed, nothing sampled) starts a fresh window instead of a flat line.
function pushSample(history, traffic, now, cap) {
  var h = Array.isArray(history) ? history : []
  if (!traffic || !traffic.iface) return h
  var last = h.length ? h[h.length - 1] : null
  var out = last && now - last.t < 6000 ? h.slice(Math.max(0, h.length - (cap || LIVE_SAMPLES) + 1)) : []
  var apps = {}, list = traffic.apps || []
  for (var i = 0; i < list.length; i++) apps[list[i].name] = (apps[list[i].name] || 0) + (list[i].down || 0)
  out.push({ t: now, down: traffic.iface.down || 0, up: traffic.iface.up || 0, apps: apps })
  return out
}

// 1 / 2 / 2.5 / 5 × 10^k at or above v.
function niceCeil(v) {
  if (!(v > 0)) return 1
  var p = Math.pow(10, Math.floor(Math.log(v) / Math.LN10)), m = v / p
  var n = m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10
  return n * p
}

// Stacked layers for the Live chart: the top N apps by download over the
// window, then "Other" (the rest of the interface: small apps, UDP, headers).
function liveSeries(history, n, units) {
  var h = Array.isArray(history) ? history : [], sums = {}, names = [], i, k
  for (i = 0; i < h.length; i++) for (k in h[i].apps) sums[k] = (sums[k] || 0) + h[i].apps[k]
  for (k in sums) if (sums[k] > 0) names.push(k)
  names.sort(function(a, b) { return sums[b] - sums[a] || (a < b ? -1 : 1) })
  names = names.slice(0, n || 4)
  var layers = [], other = [], total = [], peak = 0
  for (k = 0; k < names.length; k++) layers.push([])
  for (i = 0; i < h.length; i++) {
    var s = h[i], used = 0
    for (k = 0; k < names.length; k++) { var v = s.apps[names[k]] || 0; layers[k].push(v); used += v }
    var tot = Math.max(s.down || 0, used)
    other.push(tot - used)
    total.push(tot)
    peak = Math.max(peak, tot)
  }
  var span = h.length > 1 ? (h[h.length - 1].t - h[0].t) / 1000 : 0
  // Round axis in the display unit so the grid reads "12.5 / 25" Mbit/s or "1 / 2" MB/s.
  var max = units === "mbyte" ? niceCeil(Math.max(peak / 1e6, 0.01)) * 1e6
    : niceCeil(Math.max(peak * 8 / 1e6, 0.1)) * 1e6 / 8
  return { names: names, layers: layers, other: other, total: total, peak: peak, max: max, span: span, count: h.length }
}

// ------------------------------------------------------- bar widget ---
// Capped apps (and the whole-connection cap) with their live rate.
function capUse(cfg, traffic) {
  var out = [], list = appList(cfg), c = cfg || DEFAULTS
  for (var i = 0; i < list.length; i++) {
    var a = appCfg(cfg, list[i].key)
    if (!isCapped(a)) continue
    var live = liveOf(traffic, list[i].key)
    out.push({ label: list[i].label, down: live.down, up: live.up, capDown: clampMbit(a.downMbit), capUp: clampMbit(a.upMbit), seen: live.seen })
  }
  if (clampMbit(c.downMbit) > 0 || clampMbit(c.upMbit) > 0) {
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
  var list = appList(cfg), names = []
  for (var i = 0; i < list.length; i++)
    if (isCapped(appCfg(cfg, list[i].key))) names.push(list[i].label)
  bits = bits.concat(names.length > 3 ? names.slice(0, 2).concat(["+" + (names.length - 2) + " apps"]) : names)
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
