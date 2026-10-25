import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"
import "../Model.js" as Model

// "↓ 21.4 Mbit/s  ↑ 768 kbit/s" (or byte totals) with a caption on the right.
Item {
  id: root

  property real down: 0
  property real up: 0
  property bool bytes: false
  property bool measuring: false
  property string units: "mbit"
  property string caption: ""

  implicitHeight: Style.space(34)
  height: implicitHeight

  function fmt(v) { return root.bytes ? Model.formatBytes(v) : Model.formatRate(v, root.units) }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(12)

    Text {
      id: big
      text: root.measuring ? "Measuring…" : "↓ " + root.fmt(root.down)
      color: root.measuring ? Theme.dim : Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.heading
      font.bold: !root.measuring
    }
    Text {
      anchors.baseline: big.baseline
      visible: !root.measuring
      text: "↑ " + root.fmt(root.up)
      color: Theme.dim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.body
    }
  }
  Text {
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    text: root.caption
    color: Theme.faint
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
  }
}
