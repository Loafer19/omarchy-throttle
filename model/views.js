.pragma library
.import "../defaults.js" as Defaults
.import "format.js" as Format
.import "apps.js" as Apps
.import "live.js" as Live

// Tabs and the flat row lists the panel's ListView shows.
var DEFAULTS = Defaults.CONFIG
var MAX_APPS = Apps.MAX_APPS
var appList = Apps.appList
var findApp = Apps.findApp
var appCfg = Apps.appCfg
var isCapped = Apps.isCapped
var validProc = Apps.validProc
var knownProc = Apps.knownProc
var canAdd = Apps.canAdd
var candidates = Apps.candidates
var clampMbit = Format.clampMbit
var formatRate = Format.formatRate
var appSubtitle = Apps.appSubtitle
var liveOf = Apps.liveOf
var keyOfLabel = Apps.keyOfLabel
var appState = Apps.appState
var liveSeries = Live.liveSeries
var formatBytes = Format.formatBytes

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

// While paused nothing is shaped, so "Limited" would be a lie.
function pausedWording(cfg, sub) {
  return cfg && cfg.enabled === false && sub.indexOf("Limited") === 0 ? "Paused" + sub.slice(7) : sub
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

function gamesSafeSubtitle(a, label) {
  return a.gamesSafe
    ? "Only TCP transfers over " + a.bulkMiB + " MiB are capped — game UDP, calls and small requests stay fast"
    : "Everything " + label + " and its children send is capped"
}

// Limits › Apps › <app>: breadcrumb, hero, the two caps and Games-safe.
function detailRows(cfg, status, traffic, key, limiting, units) {
  var app = findApp(cfg, "key", key)
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
