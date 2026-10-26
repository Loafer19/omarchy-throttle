pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"
import "../model/format.js" as Format
import "../model/live.js" as Live

// Traffic › Live: download over the last 90 s, stacked per app (top four by
// volume in accent shades, "Other" = the rest of the interface incl. UDP).
Item {
  id: root

  property var series: ({ names: [], layers: [], other: [], total: [], peak: 0, max: 1, count: 0 })
  property string units: "mbit"
  readonly property int slots: Live.LIVE_SAMPLES
  readonly property var alphas: [1, 0.66, 0.42, 0.26]
  readonly property int plotHeight: Style.space(118)
  readonly property int axisHeight: Style.space(16)

  implicitHeight: plotHeight + axisHeight + legend.height + Style.space(6)
  height: implicitHeight

  function css(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
  }
  function layerColor(i) { return i < 0 ? css(Theme.fg, 0.16) : css(Theme.accent, alphas[Math.min(i, alphas.length - 1)]) }

  onSeriesChanged: canvas.requestPaint()

  Item {
    id: plot
    x: Theme.edge
    width: parent.width - Theme.edge * 2
    height: root.plotHeight

    // Grid: four bands; the labels are drawn after the canvas (below).
    Repeater {
      model: 4
      Rectangle {
        required property int index
        y: plot.height * (1 - (index + 1) / 4)
        width: plot.width
        height: Theme.hairline
        color: Theme.line
      }
    }
    Rectangle { y: plot.height - height; width: plot.width; height: Theme.hairline; color: Theme.tint(Theme.fg, 0.24) }

    Canvas {
      id: canvas
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var s = root.series, n = s.count
        if (!n || n < 2) return
        var step = width / (root.slots - 1)
        var x0 = width - (n - 1) * step
        var base = []
        for (var i = 0; i < n; i++) base.push(0)
        var stack = s.layers.slice()
        stack.push(s.other)
        for (var k = 0; k < stack.length; k++) {
          var layer = stack[k], top = []
          for (i = 0; i < n; i++) top.push(base[i] + (layer[i] || 0))
          ctx.beginPath()
          for (i = 0; i < n; i++) ctx.lineTo(x0 + i * step, height - height * Math.min(1, top[i] / s.max))
          for (i = n - 1; i >= 0; i--) ctx.lineTo(x0 + i * step, height - height * Math.min(1, base[i] / s.max))
          ctx.closePath()
          ctx.fillStyle = root.layerColor(k < s.layers.length ? k : -1)
          ctx.fill()
          base = top
        }
        // Total outline on top.
        ctx.beginPath()
        for (i = 0; i < n; i++) ctx.lineTo(x0 + i * step, height - height * Math.min(1, base[i] / s.max))
        ctx.strokeStyle = root.css(Theme.fg, 0.55)
        ctx.lineWidth = 1
        ctx.stroke()
      }
    }

    // Labels at the top-left of every other gridline, on a backdrop so a
    // full history (which paints over the lower lines) doesn't hide them.
    Repeater {
      model: [0.5, 1]
      Rectangle {
        id: gridLabel
        required property real modelData
        y: plot.height * (1 - modelData) + Style.space(2)
        width: labelText.implicitWidth + Style.space(8)
        height: labelText.implicitHeight + Style.space(2)
        radius: Style.cornerRadius
        color: Theme.tint(Theme.background, 0.72)
        Text {
          id: labelText
          anchors.centerIn: parent
          text: Format.formatRate(root.series.max * gridLabel.modelData, root.units).replace(".0 ", " ")
          color: Theme.dim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.caption
        }
      }
    }

    Text {
      anchors.centerIn: parent
      visible: root.series.count < 2
      text: "Collecting samples…"
      color: Theme.faint
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }

  // Time axis.
  Repeater {
    model: [{ t: "−90 s", f: 0 }, { t: "−60 s", f: 1 / 3 }, { t: "−30 s", f: 2 / 3 }, { t: "now", f: 1 }]
    Text {
      id: tick
      required property var modelData
      y: root.plotHeight + Style.space(3)
      x: Theme.edge + plot.width * tick.modelData.f - (tick.modelData.f === 0 ? 0 : tick.modelData.f === 1 ? width : width / 2)
      text: tick.modelData.t
      color: Theme.faint
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }

  Flow {
    id: legend
    x: Theme.edge
    y: root.plotHeight + root.axisHeight + Style.space(2)
    width: parent.width - Theme.edge * 2
    spacing: Style.space(12)
    visible: root.series.count >= 2

    Repeater {
      model: root.series.names.length + 1
      Row {
        id: entry
        required property int index
        readonly property bool isOther: entry.index >= root.series.names.length
        spacing: Style.space(5)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(8); height: width
          radius: Style.cornerRadius
          color: entry.isOther ? Theme.tint(Theme.fg, 0.16) : Theme.tint(Theme.accent, root.alphas[Math.min(entry.index, 3)])
        }
        Text {
          textFormat: Text.PlainText
          text: entry.isOther ? "Other · UDP" : root.series.names[entry.index]
          color: Theme.dim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.caption
        }
      }
    }
  }
}
