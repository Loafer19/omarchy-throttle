import QtQuick
import qs.Commons
import qs.Ui
import "../theme"

// Section label (the shell's PanelSectionHeader) with an optional caption on the right.
Item {
  id: root

  property string title: ""
  property string caption: ""

  implicitHeight: Style.space(30)
  height: implicitHeight

  PanelSectionHeader {
    id: head
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(4)
    text: root.title.toUpperCase()
    foreground: Theme.fg
    fontFamily: Theme.fontFamily
  }
  Text {
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.left: head.right
    anchors.leftMargin: Theme.gap
    anchors.baseline: head.baseline
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    visible: root.caption !== ""
    textFormat: Text.PlainText
    text: root.caption
    color: Theme.faint
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
  }
}
