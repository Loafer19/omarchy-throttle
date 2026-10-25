import QtQuick
import qs.Commons
import "../theme"

// Footer: "Tab tabs · h l sub-tabs · j k rows · Enter open · p pause".
Row {
  id: root

  property var hints: []

  spacing: Style.space(10)

  Repeater {
    model: root.hints
    Row {
      required property var modelData
      spacing: Style.space(4)
      Text {
        text: modelData[0]
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.caption
        font.bold: true
      }
      Text {
        text: modelData[1]
        color: Theme.faint
        font.family: Theme.fontFamily
        font.pixelSize: Theme.caption
      }
    }
  }
}
