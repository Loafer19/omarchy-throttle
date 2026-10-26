import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"

// Under the tabs: the status line ("Limiting on eth0 · Heroic") and the
// On / Paused chip (p).
Item {
  id: root

  property string text: ""
  property color textColor: Theme.dim
  property bool on: true
  property bool canToggle: true
  signal toggleRequested()

  width: parent ? parent.width : 0
  height: Style.space(24)

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.right: onChip.left
    anchors.rightMargin: Theme.gap
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: root.text
    color: root.textColor
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
  }

  HeaderChip {
    id: onChip
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    text: root.on ? "On" : "Paused"
    on: root.on
    enabled: root.canToggle
    tooltipText: root.on ? "Pause every limit (p) — settings are kept" : "Resume limits (p)"
    onClicked: root.toggleRequested()
  }
}
