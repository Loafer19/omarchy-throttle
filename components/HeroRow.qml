import QtQuick
import qs.Commons
import qs.Ui
import "../theme"

// Top of an app's detail page: name, live state, its processes, the live
// rate against the cap, and (custom apps) Remove, which asks once.
CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property string status: "idle"
  property string trailing: ""
  property bool removable: false
  property bool armed: false

  signal rowHovered()
  signal removeClicked()

  implicitHeight: Math.max(Style.space(52), col.implicitHeight + Style.space(16))
  height: implicitHeight
  foreground: Theme.fg
  fill: Theme.hoverFill
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
    onContainsMouseChanged: if (containsMouse && root.removable) root.rowHovered()
  }

  StateDot {
    id: dot
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    y: col.y + nameText.height / 2 - height / 2
    status: root.status
  }

  Column {
    id: col
    anchors.left: dot.right
    anchors.leftMargin: Style.space(8)
    anchors.right: rightBox.left
    anchors.rightMargin: Theme.gap
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      id: nameText
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.title
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.title
      font.bold: true
    }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.subtitle
      color: root.status === "refused" ? Theme.urgent : Theme.dim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }

  Row {
    id: rightBox
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.gap

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.trailing !== ""
      text: root.trailing
      color: root.status === "limited" ? Theme.fg : Theme.dim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
      font.bold: root.status === "limited"
    }
    HeaderChip {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.removable
      text: root.armed ? "Confirm" : "Remove"
      on: root.armed
      danger: true
      tooltipText: root.armed ? "Click again to remove this app and its caps" : "Stop limiting this app and remove it from the list"
      onClicked: root.activate()
    }
  }
}
