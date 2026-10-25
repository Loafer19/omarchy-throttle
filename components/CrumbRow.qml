import QtQuick
import qs.Commons
import qs.Ui
import "../theme"

// "‹ Apps / Heroic": back to the list (also Esc).
CursorSurface {
  id: root

  property string parentTitle: "Apps"
  property string title: ""

  signal rowHovered()
  signal rowClicked()

  implicitHeight: Theme.smallRowHeight
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

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    Text {
      text: "‹  " + root.parentTitle
      color: root.hasCursor ? Theme.fg : Theme.dim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
      font.bold: root.hasCursor
    }
    Text { text: "/"; color: Theme.faint; font.family: Theme.fontFamily; font.pixelSize: Theme.caption }
    Text {
      textFormat: Text.PlainText
      text: root.title
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    text: "Esc"
    color: Theme.faint
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
  }
}
