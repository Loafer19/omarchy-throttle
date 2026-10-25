import QtQuick
import qs.Commons
import qs.Ui
import "../theme"

// Small action chip (same look as System Tidy / Notification Center).
Rectangle {
  id: root

  property string text: ""
  property string tooltipText: ""
  property bool on: false
  property bool enabled: true
  // When on+danger, fill with urgent (destructive confirms like Remove).
  property bool danger: false

  signal clicked()

  readonly property color activeFill: root.danger ? Theme.urgent : Theme.accent
  readonly property color idleFill: Style.normalFillFor(Theme.fg, Theme.accent, Theme.urgent)

  width: label.implicitWidth + Style.space(16)
  height: Style.space(24)
  radius: Style.cornerRadius
  opacity: root.enabled ? 1 : 0.4
  color: {
    if (!root.enabled) return root.idleFill
    if (root.on) return chipMouse.containsMouse ? Qt.darker(root.activeFill, 1.08) : root.activeFill
    return chipMouse.containsMouse ? Theme.hoverFill : root.idleFill
  }
  border.width: Style.spacing.hairline
  border.color: root.on && root.enabled ? root.activeFill : Theme.line

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.on && root.enabled ? Theme.background : Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
    font.bold: true
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && chipMouse.containsMouse
    text: root.tooltipText
    fontFamily: Theme.fontFamily
  }
}
