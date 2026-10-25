import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"

// limited (accent) · running (fg) · idle (faint) · refused (urgent)
Rectangle {
  property string status: "idle"
  width: Style.space(7)
  height: width
  radius: width / 2
  color: status === "limited" ? Theme.accent
    : status === "refused" ? Theme.urgent
    : status === "running" ? Theme.fg : Theme.tint(Theme.fg, 0.25)
}
