import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"

// One-time setup card: the helper that touches tc/nft needs root once.
Rectangle {
  id: root

  property string command: ""
  signal copyRequested()

  width: parent ? parent.width : 0
  height: visible ? setupCol.implicitHeight + Style.space(16) : 0
  radius: Style.cornerRadius
  color: Theme.tint(Theme.accent, 0.12)
  border.width: Style.space(1)
  border.color: Theme.tint(Theme.accent, 0.4)

  Column {
    id: setupCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    spacing: Style.space(6)

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: "One-time setup: shaping needs a tiny root helper. Run this once in a terminal:"
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }

    Row {
      width: parent.width
      spacing: Theme.gap

      TextEdit {
        width: parent.width - copyChip.width - Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        text: root.command
        color: Theme.fg
        font.family: "monospace"
        font.pixelSize: Theme.caption
      }

      HeaderChip {
        id: copyChip
        anchors.verticalCenter: parent.verticalCenter
        text: copied.running ? "Copied" : "Copy"
        tooltipText: "Copy the command to the clipboard"
        onClicked: {
          root.copyRequested()
          copied.restart()
        }
        Timer { id: copied; interval: 1500 }
      }
    }
  }
}
