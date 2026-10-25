import qs.Commons as Commons
import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Per-day bars (download solid, upload faint on top) for the Stats tab.
Item {
  id: root

  property var bars: []
  property real peak: 1
  property color contentForeground: Commons.Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  readonly property int labelHeight: Style.space(16)
  readonly property real slot: bars.length > 0 ? (width - edgeMargin * 2) / bars.length : 0

  implicitHeight: Style.space(118)
  height: implicitHeight

  Text {
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.top: parent.top
    text: "peak " + Model.formatBytes(root.peak) + "/day"
    color: Qt.darker(root.contentForeground, 1.8)
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    x: root.edgeMargin
    width: parent.width - root.edgeMargin * 2
    y: parent.height - root.labelHeight
    height: Style.spacing.hairline
    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
  }

  Repeater {
    model: root.bars.length

    Item {
      id: barSlot
      required property int index
      readonly property var bar: root.bars[index] || ({})
      readonly property real area: root.height - root.labelHeight - Style.space(18)
      x: root.edgeMargin + index * root.slot
      width: root.slot
      height: root.height

      Rectangle {
        id: downBar
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(2, root.slot * 0.62)
        y: root.height - root.labelHeight - height
        height: Math.max(barSlot.bar.down > 0 ? 2 : 0, barSlot.area * (barSlot.bar.down || 0) / Math.max(1, root.peak))
        radius: Math.min(Style.cornerRadius, width / 4)
        color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b,
          barSlot.bar.inRange ? (barSlot.bar.today ? 1 : 0.72) : 0.28)
      }
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: downBar.width
        y: downBar.y - height
        height: Math.max(0, barSlot.area * (barSlot.bar.up || 0) / Math.max(1, root.peak))
        radius: downBar.radius
        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b,
          barSlot.bar.inRange ? 0.35 : 0.12)
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // 30-day view: label every 5th day plus today.
        visible: root.bars.length <= 7 || barSlot.bar.today || barSlot.index % 5 === 0
        text: barSlot.bar.today && root.bars.length <= 7 ? "Today" : (barSlot.bar.label || "")
        color: barSlot.bar.today ? root.contentForeground : Qt.darker(root.contentForeground, 1.6)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        font.bold: barSlot.bar.today === true
      }
    }
  }
}
