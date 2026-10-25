import qs.Commons as Commons
import QtQuick
import qs.Commons
import qs.Ui

// App heading in the Apps tab: name, live state, what else shares its cgroup,
// and (custom apps) a Remove chip that asks once before it removes.
CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property bool running: false
  property bool limited: false
  property bool showDot: true
  property bool removable: false
  property bool armed: false
  property color contentForeground: Commons.Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  signal rowHovered()
  signal removeClicked()

  implicitHeight: col.implicitHeight + Style.space(14)
  height: implicitHeight
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Commons.Color.accent, Commons.Color.urgent)
  bordered: false

  // A second click (or Enter) within 3 s confirms.
  function activate() {
    if (!root.removable) return
    if (root.armed) { root.armed = false; root.removeClicked() }
    else { root.armed = true; disarm.restart() }
  }
  Timer { id: disarm; interval: 3000; onTriggered: root.armed = false }
  onHasCursorChanged: if (!hasCursor) armed = false

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
  }

  Rectangle {
    id: dot
    visible: root.showDot
    anchors.left: parent.left
    anchors.leftMargin: root.edgeMargin
    anchors.top: parent.top
    anchors.topMargin: Style.space(14) + Style.space(2)
    width: root.showDot ? Style.space(7) : 0
    height: width
    radius: width / 2
    color: root.limited ? Commons.Color.accent
      : (root.running ? root.contentForeground : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.25))
  }

  Column {
    id: col
    anchors.left: root.showDot ? dot.right : parent.left
    anchors.leftMargin: root.showDot ? Style.space(8) : root.edgeMargin
    anchors.right: removeChip.visible ? removeChip.left : parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(4)
    spacing: Style.space(2)

    Text {
      width: parent.width
      elide: Text.ElideRight
      text: root.title
      textFormat: Text.PlainText
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

  HeaderChip {
    id: removeChip
    visible: root.removable
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(8)
    text: root.armed ? "Confirm" : "Remove"
    on: root.armed
    danger: true
    contentForeground: root.contentForeground
    contentFontFamily: root.contentFontFamily
    tooltipText: root.armed ? "Click again to remove this app and its caps" : "Stop limiting this app and remove it from the list"
    onClicked: root.activate()
  }
}
