.pragma library
.import "../defaults.js" as Defaults
.import "format.js" as Format

// Configured apps: lookup, validation, add/remove patches, per-app status.
var DEFAULTS = Defaults.CONFIG
var clampMbit = Format.clampMbit
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

// First app in appList(cfg) whose `field` equals `value`, or null.
function findApp(cfg, field, value) {
  var list = appList(cfg)
  for (var i = 0; i < list.length; i++) if (list[i][field] === value) return list[i]
  return null
}

function appLabel(cfg, key) {
  var app = findApp(cfg, "key", key)
  return app ? app.label : String(key)
}

// An app's settings (or the whole-connection cfg) with a download or upload cap.
function isCapped(a) { return !!a && (clampMbit(a.downMbit) > 0 || clampMbit(a.upMbit) > 0) }

// Traffic / stats rows are named by label; is that app capped right now?
function labelCapped(cfg, label) {
  return appList(cfg).some(function(app) { return app.label === label && isCapped(appCfg(cfg, app.key)) })
}

// Any cap at all: the whole connection or one of the apps.
function anyCap(cfg) {
  if (!cfg) return false
  if (isCapped(cfg)) return true
  var apps = cfg.apps || {}
  for (var k in apps) if (isCapped(apps[k])) return true
  return false
}

function validProc(name) {
  var n = String(name || "")
  return PROC_RE.test(n) && DEFAULTS.denyProcs.indexOf(n) < 0
}

function knownProc(cfg, name) {
  return appList(cfg).some(function(app) { return app.procs.indexOf(name) >= 0 })
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

// "limited" (accent dot) · "running" · "idle" (not running) · "refused".
function appState(status, cfg, key, limiting) {
  var s = appStatus(status, key)
  if (!s.running) return "idle"
  if (s.refused && s.refused.length && !(s.cgroups && s.cgroups.length)) return "refused"
  if (limiting && s.cgroups && s.cgroups.length && isCapped(appCfg(cfg, key))) return "limited"
  return "running"
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
  var app = findApp(cfg, "label", label)
  return app ? app.key : ""
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
