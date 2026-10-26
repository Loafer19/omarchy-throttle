.pragma library
.import "../defaults.js" as Defaults
.import "apps.js" as Apps
.import "rates.js" as Rates

// Settings tab rows and the patches its choices produce.
var DEFAULTS = Defaults.CONFIG
var appList = Apps.appList
var appCfg = Apps.appCfg
var STEP_SETS = Rates.STEP_SETS
var stepsOf = Rates.stepsOf
var UNIT_CHOICES = [{ key: "mbit", label: "Mbit/s" }, { key: "mbyte", label: "MB/s" }]
var WIDGET_CHOICES = [{ key: "icon", label: "Icon" }, { key: "dot", label: "Icon + dot" }, { key: "rate", label: "Icon + rate" }]
var BULK_CHOICES = [2, 4, 8, 16]
var KEEP_CHOICES = [7, 35, 90]

// [2, 4, 8] → chips "2", "4", "8 MiB": the unit only on the last one.
function numberChoices(values, unit) {
  return values.map(function(v, i) { return { key: String(v), label: v + (i === values.length - 1 ? unit : "") } })
}

function stepsKey(list) { return list.join(",") }

function bulkOf(cfg) { var l = appList(cfg); return l.length ? appCfg(cfg, l[0].key).bulkMiB : DEFAULTS.custom.bulkMiB }

function settingsRows(cfg, status, installed) {
  var c = cfg || DEFAULTS, steps = stepsOf(c).slice(1)
  var stepOpts = [], i
  for (i = 0; i < STEP_SETS.length; i++) stepOpts.push({ key: stepsKey(STEP_SETS[i]), label: STEP_SETS[i].join("/") })
  if (stepOpts.map(function(o) { return o.key }).indexOf(stepsKey(steps)) < 0)
    stepOpts.push({ key: stepsKey(steps), label: steps.join("/") })
  var bulkOpts = numberChoices(BULK_CHOICES, " MiB"), keepOpts = numberChoices(KEEP_CHOICES, " days")
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
