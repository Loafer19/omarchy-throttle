.pragma library
.import "views.js" as Views

// Keyboard cursor over the panel: tabs → filters (sub-tabs) → rows, as in
// System Tidy. Pure helpers; Panel.qml owns the state and applies results.

function firstSelectable(rows) { return nextSelectable(rows, -1, 1) }

// Next row from `from` (exclusive) in direction dir (±1) the cursor may land on, or -1.
function nextSelectable(rows, from, dir) {
  for (var i = from + dir; i >= 0 && i < rows.length; i += dir) if (Views.selectableRow(rows[i])) return i
  return -1
}

// Index of the chip whose key is `key` (0 if none).
function chipIndex(chips, key) {
  for (var i = 0; i < chips.length; i++) if (String(chips[i].key) === String(key)) return i
  return 0
}

// i + dir, wrapping around n items (Tab / Shift+Tab).
function cycleIndex(i, dir, n) { return ((i + dir) % n + n) % n }

function clampIndex(i, n) { return Math.max(0, Math.min(n - 1, i)) }

// Where j/k (dy = ±1) moves the cursor: { section, index?, top? } or null to
// stay. Chip sections come without an index (the active chip is meant);
// top: the list should scroll back to its beginning.
function verticalTarget(section, index, rows, hasFilters, dy) {
  var first = firstSelectable(rows)
  if (section === "tabs") {
    if (dy < 0) return null
    if (hasFilters) return { section: "filters" }
    return first >= 0 ? { section: "rows", index: first } : null
  }
  if (section === "filters") {
    if (dy < 0) return { section: "tabs" }
    return first >= 0 ? { section: "rows", index: first } : null
  }
  var next = nextSelectable(rows, index, dy > 0 ? 1 : -1)
  if (next >= 0) return { section: "rows", index: next }
  if (dy < 0) return { section: hasFilters ? "filters" : "tabs", top: true }
  return null
}

// Footer key hints for the current view: [[keys, what], ...].
function keyHints(v) {
  var tail = [["p", "pause"]]
  if (v.section === "filters" && v.cursorActive) return [["h l", v.tab === "traffic" ? "range" : "sub-tabs"], ["j", "rows"], ["Tab", "tabs"]].concat(tail)
  if (v.inDetail) return [["Esc", "back"], ["j k", "rows"], ["h l", "change"], ["Enter", "toggle"]].concat(tail)
  if (v.tab === "settings") return [["Tab", "tabs"], ["j k", "rows"], ["h l", "change"], ["Enter", "next"]].concat(tail)
  if (v.tab === "traffic") return [["Tab", "tabs"], ["h l", "range"], ["j k", "rows"], ["Enter", "open · add"]].concat(tail)
  if (v.limitsSub === "connection") return [["Tab", "tabs"], ["j k", "rows"], ["h l", "change"]].concat(tail)
  if (v.limitsSub === "add") return [["Tab", "tabs"], ["j k", "rows"], ["Enter", "add"]].concat(tail)
  return [["Tab", "tabs"], ["h l", "sub-tabs"], ["j k", "rows"], ["Enter", "open"]].concat(tail)
}
