.pragma library
.import "../defaults.js" as Defaults
.import "format.js" as Format

// Rate chips and steps for the Download / Upload rows.
var DEFAULTS = Defaults.CONFIG
var clampMbit = Format.clampMbit

var PRESETS = [0, 10, 25, 50, 100]

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
