import qs.Commons as Commons
import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property bool checked: false
  property color contentForeground: Commons.Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  signal rowHovered()
  signal rowClicked()

  implicitHeight: Math.max(Style.space(52), infoCol.implicitHeight + Style.space(14))
  height: implicitHeight
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Commons.Color.accent, Commons.Color.urgent)
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
    anchors.leftMargin: root.edgeMargin
    anchors.right: toggle.left
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.title
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      width: parent.width
      visible: root.subtitle !== ""
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.subtitle
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    interactive: false
  }
}
