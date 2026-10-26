.pragma library

// Units and number formatting: caps (Mbit/s), live rates, byte totals.

var MAX_MBIT = 10000

function clampMbit(v) {
  var n = Math.floor(Number(v))
  if (!isFinite(n) || n < 0) return 0
  return n > MAX_MBIT ? MAX_MBIT : n
}

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

function formatBytes(n) {
  var b = Number(n || 0)
  if (b < 1024) return b.toFixed(0) + " B"
  if (b < 1048576) return (b / 1024).toFixed(0) + " KiB"
  if (b < 1073741824) return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + " MiB"
  return (b / 1073741824).toFixed(b < 10737418240 ? 2 : 1) + " GiB"
}

// Mbit/s cap → bytes/s, for comparing with live rates.
// A row's amount: a byte total (history) or a live rate.
function formatAmount(n, bytes, units) { return bytes ? formatBytes(n) : formatRate(n, units) }

function capBytes(mbit) { return clampMbit(mbit) * 125000 }

// 1 / 2 / 2.5 / 5 × 10^k at or above v.
function niceCeil(v) {
  if (!(v > 0)) return 1
  var p = Math.pow(10, Math.floor(Math.log(v) / Math.LN10)), m = v / p
  var n = m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10
  return n * p
}
