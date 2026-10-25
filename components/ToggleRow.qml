import QtQuick
import qs.Commons
import qs.Ui
import "../theme"

CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property bool checked: false

  signal rowHovered()
  signal rowClicked()

  implicitHeight: Math.max(Theme.rowHeight, infoCol.implicitHeight + Style.space(14))
  height: implicitHeight
  foreground: Theme.fg
  fill: Theme.hoverFill
  bordered: false

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
    onClicked: root.rowClicked()
  }

  Column {
    id: infoCol
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.right: toggle.left
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
      visible: root.subtitle !== ""
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.subtitle
      color: Theme.dim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    interactive: false
  }
}
