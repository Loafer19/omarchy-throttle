.pragma library
.import "format.js" as Format

// Traffic › Live: the sample ring buffer and the stacked chart series.
var niceCeil = Format.niceCeil

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
