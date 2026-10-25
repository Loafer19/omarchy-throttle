import QtQuick
import qs.Commons
import "../theme"

// "↓ 10" cap tag: accent outline when set, faint "↓ Off" when not.
Rectangle {
  id: root

  property string arrow: "↓"
  property int value: 0
  property bool showOff: true

  readonly property bool set: value > 0
  visible: set || showOff
  width: visible ? label.implicitWidth + Style.space(10) : 0
  height: Style.space(18)
  radius: Style.cornerRadius
  color: set ? Theme.tint(Theme.accent, 0.12) : "transparent"
  border.width: Style.spacing.hairline
  border.color: set ? Theme.tint(Theme.accent, 0.55) : Theme.line

  Text {
    id: label
    anchors.centerIn: parent
    text: root.arrow + " " + (root.set ? root.value : "Off")
    color: root.set ? Theme.fg : Theme.faint
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
    font.bold: root.set
  }
}
