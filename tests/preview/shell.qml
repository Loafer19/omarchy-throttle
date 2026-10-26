// Offscreen panel harness for tools/render-previews.sh: the real Panel.qml on
// a FakeStore. PREVIEW_TAB / PREVIEW_SUB / PREVIEW_DETAIL pick the view; the
// card is saved to PREVIEW_OUT.
import QtQuick
import Quickshell
import "plugin" as P
import "plugin/tests/preview" as F

ShellRoot {
  id: shell
  property string tab: Quickshell.env("PREVIEW_TAB") || "limits"
  property string sub: Quickshell.env("PREVIEW_SUB") || ""
  property string detail: Quickshell.env("PREVIEW_DETAIL") || ""
  property string out: Quickshell.env("PREVIEW_OUT") || ""

  F.FakeStore { id: fake }

  FloatingWindow {
    implicitWidth: 1100
    implicitHeight: 1300
    color: "transparent"
    P.Panel { id: panel; store: fake; anchors.fill: parent }
  }

  Timer {
    interval: 1500; running: true
    onTriggered: {
      panel.open()
      panel.activeTab = shell.tab
      if (shell.sub && shell.tab === "limits") panel.limitsSub = shell.sub
      if (shell.sub && shell.tab === "traffic") panel.trafficSub = shell.sub
      if (shell.detail) panel.openApp(shell.detail)
      grab.start()
    }
  }
  Timer {
    id: grab; interval: 1500
    onTriggered: {
      var kp = panel.children.filter(function(c) { return c.card !== undefined })[0]
      kp.card.grabToImage(function(r) {
        r.saveToFile(shell.out)
        console.log("saved", shell.out, kp.card.width, kp.card.height)
        Qt.quit()
      })
    }
  }
}
