pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"

// Per-day bars (download solid, upload faint on top) for Traffic › Today / 7 / 30 days.
Item {
  id: root

  property var bars: []
  property real peak: 1
  readonly property int edgeMargin: Theme.edge

  readonly property int labelHeight: Style.space(16)
  readonly property real slot: bars.length > 0 ? (width - edgeMargin * 2) / bars.length : 0

  implicitHeight: Style.space(104)
  height: implicitHeight

  Rectangle {
    x: root.edgeMargin
    width: parent.width - root.edgeMargin * 2
    y: parent.height - root.labelHeight
    height: Style.space(1)
    color: Theme.line
  }

  Repeater {
    model: root.bars.length

    Item {
      id: barSlot
      required property int index
      readonly property var bar: root.bars[barSlot.index] || ({})
      readonly property real area: root.height - root.labelHeight - Style.space(6)
      x: root.edgeMargin + barSlot.index * root.slot
      width: root.slot
      height: root.height

      Rectangle {
        id: downBar
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(2, root.slot * 0.62)
        y: root.height - root.labelHeight - height
        height: Math.max(barSlot.bar.down > 0 ? 2 : 0, barSlot.area * (barSlot.bar.down || 0) / Math.max(1, root.peak))
        radius: Math.min(Style.cornerRadius, width / 4)
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b,
          barSlot.bar.inRange ? (barSlot.bar.today ? 1 : 0.72) : 0.28)
      }
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: downBar.width
        y: downBar.y - height
        height: Math.max(0, barSlot.area * (barSlot.bar.up || 0) / Math.max(1, root.peak))
        radius: downBar.radius
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
          barSlot.bar.inRange ? 0.35 : 0.12)
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // 30-day view: label every 5th day plus today.
        visible: root.bars.length <= 7 || barSlot.bar.today || barSlot.index % 5 === 0
        text: barSlot.bar.today && root.bars.length <= 7 ? "Today" : (barSlot.bar.label || "")
        color: barSlot.bar.today ? Theme.fg : Theme.faint
        font.family: Theme.fontFamily
        font.pixelSize: Theme.caption
        font.bold: barSlot.bar.today === true
      }
    }
  }
}
