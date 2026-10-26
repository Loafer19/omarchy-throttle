// Offscreen bar-widget harness for tools/render-previews.sh: the real
// BarWidget.qml in each mode/state on FakeStores, in one strip saved to
// PREVIEW_OUT.
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as C
import "plugin" as T
import "plugin/tests/preview" as F

ShellRoot {
  id: shell
  property string out: Quickshell.env("PREVIEW_OUT") || ""
  FloatingWindow {
    id: win
    implicitWidth: 1100; implicitHeight: 60
    color: "transparent"
    Rectangle {
      id: strip
      width: row.width + 24; height: 40
      color: C.Color.background
      Row {
        id: row
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 28
        Repeater {
          model: [
            { mode: "icon", paused: false, error: "", down: 1235000, label: "icon · limiting" },
            { mode: "icon", paused: false, error: "", down: 1235000, label: "icon · idle", nolimit: true },
            { mode: "dot", paused: false, error: "", down: 1235000, label: "dot · cap maxed" },
            { mode: "rate", paused: false, error: "", down: 1235000, label: "rate" },
            { mode: "icon", paused: true, error: "", down: 0, label: "paused" },
            { mode: "icon", paused: false, error: "tc failed", down: 0, label: "error" },
            { mode: "dot", paused: false, error: "", down: 1235000, label: "dot · vertical bar", vertical: true },
            { mode: "rate", paused: false, error: "", down: 1235000, label: "rate · vertical (icon only)", vertical: true }
          ]
          Row {
            required property var modelData
            spacing: 6
            height: 28
            Item {
              id: slot
              width: modelData.vertical ? 28 : w.implicitWidth; height: w.implicitHeight > 0 ? w.implicitHeight : 26
              F.FakeStore {
                id: st
                mode: modelData.mode; paused: modelData.paused; error: modelData.error; heroicDown: modelData.down; noLimit: modelData.nolimit === true
              }
              QtObject {
                id: fakeBar
                property color barForeground: C.Color.foreground
                property color foreground: C.Color.foreground
                property string fontFamily: C.Style.font.family
                property bool vertical: modelData.vertical === true
                property int barSize: modelData.vertical ? 28 : 26
                property bool foregroundAnimationEnabled: false
                function showTooltip() {} function hideTooltip() {}
                property color urgent: C.Color.urgent
                property var shell: QtObject { function serviceFor(n) { return st } }
              }
              T.BarWidget { id: w; bar: fakeBar; width: parent.width; height: parent.height }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: Qt.darker(C.Color.foreground, 1.8); font.family: C.Style.font.family; font.pixelSize: 10 }
          }
        }
      }
    }
  }
  Timer {
    interval: 3000; running: true
    onTriggered: strip.grabToImage(function(r) { r.saveToFile(shell.out); console.log("saved", shell.out); Qt.quit() })
  }
}
