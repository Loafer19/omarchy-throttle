import QtQuick
import qs.Commons
import qs.Ui
import "../vendor/yoyo-ui"

// Settings: title + one-line caption, the options as compact chips.
CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property var options: []
  property string value: ""

  signal rowHovered()
  signal picked(string key)

  implicitHeight: Theme.rowHeight
  height: implicitHeight
  foreground: Theme.fg
  fill: Theme.hoverFill
  bordered: false

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
  }

  Column {
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.right: chips.left
    anchors.rightMargin: Theme.gap
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.title
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.body
      font.bold: true
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.subtitle
      color: Theme.dim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }

  ChipRow {
    id: chips
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    compact: true
    chips: root.options
    selectedKey: root.value
    onSelected: function(key) { root.picked(key) }
    onChipHovered: function(index) { root.rowHovered() }
  }
}
