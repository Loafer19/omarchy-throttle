import QtQuick
import qs.Commons
import qs.Ui
import "../vendor/yoyo-ui"

// Limits › Apps: one compact row per app (or the whole-connection link).
// Enter / click drills into the app.
CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property string status: "idle"
  property bool showDot: true
  property int down: 0
  property int up: 0

  signal rowHovered()
  signal rowClicked()

  implicitHeight: Theme.rowHeight
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

  StateDot {
    id: dot
    visible: root.showDot
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.verticalCenter: titleText.verticalCenter
    status: root.status
  }

  Text {
    id: titleText
    anchors.left: root.showDot ? dot.right : parent.left
    anchors.leftMargin: root.showDot ? Style.space(8) : Theme.edge
    anchors.right: tags.left
    anchors.rightMargin: Theme.gap
    anchors.bottom: parent.verticalCenter
    anchors.bottomMargin: Style.space(1)
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: root.title
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.body
    font.bold: true
  }
  Text {
    anchors.left: titleText.left
    anchors.right: titleText.right
    anchors.top: parent.verticalCenter
    anchors.topMargin: Style.space(1)
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: root.subtitle
    color: root.status === "refused" ? Theme.urgent : Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
  }

  Row {
    id: tags
    anchors.right: chevron.left
    anchors.rightMargin: Theme.gap
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)
    CapTag { arrow: "↓"; value: root.down }
    CapTag { arrow: "↑"; value: root.up }
  }

  Text {
    id: chevron
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    text: "›"
    color: root.hasCursor ? Theme.fg : Theme.faint
    font.family: Theme.fontFamily
    font.pixelSize: Theme.heading
  }
}
