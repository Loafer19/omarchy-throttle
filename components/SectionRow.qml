import qs.Commons as Commons
import QtQuick
import qs.Commons

// App heading in the Apps tab: name, live state, and what else shares its cgroup.
Item {
  id: root

  property string title: ""
  property string subtitle: ""
  property bool running: false
  property bool limited: false
  property color contentForeground: Commons.Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  implicitHeight: col.implicitHeight + Style.space(14)
  height: implicitHeight

  Rectangle {
    id: dot
    anchors.left: parent.left
    anchors.leftMargin: root.edgeMargin
    anchors.top: parent.top
    anchors.topMargin: Style.space(14) + Style.space(2)
    width: Style.space(7)
    height: width
    radius: width / 2
    color: root.limited ? Commons.Color.accent
      : (root.running ? root.contentForeground : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.25))
  }

  Column {
    id: col
    anchors.left: dot.right
    anchors.leftMargin: Style.space(8)
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(2)
    spacing: Style.space(2)

    Text {
      text: root.title
      textFormat: Text.PlainText
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.subtitle
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
