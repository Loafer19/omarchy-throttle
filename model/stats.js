.pragma library

// Traffic › Today / 7 days / 30 days: range totals and per-day bars.

var RANGES = [
  { key: "today", label: "Today", days: 1, chart: 7 },
  { key: "week", label: "7 days", days: 7, chart: 7 },
  { key: "month", label: "30 days", days: 30, chart: 30 }
]

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
