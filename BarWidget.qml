import qs.Commons as Commons
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "yoyo.throttle"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "yoyo.throttle"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function pause(): void { if (root.panelItem && root.panelItem.store) root.panelItem.store.setEnabled(false) }
    function resume(): void { if (root.panelItem && root.panelItem.store) root.panelItem.store.setEnabled(true) }
  }

  readonly property var panelItem: panelLoader.item
  readonly property var store: panelItem ? panelItem.store : null
  readonly property bool limiting: store ? store.limiting === true : false
  readonly property bool paused: store ? (store.cfg && store.cfg.enabled === false) : false
  readonly property bool failing: store && store.status ? (store.status.error || "") !== "" : false

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-speedometer_slow while limiting, nf-md-speedometer otherwise.
    text: root.limiting ? "\uDB83\uDF86" : "\uDB81\uDCC5"
    active: root.limiting || root.failing
    activeColor: root.failing ? Commons.Color.urgent : Commons.Color.accent
    dimmed: root.paused
    tooltipText: {
      if (!root.store || !root.store.status) return "Throttle"
      if (root.store.status.helper !== "installed") return "Throttle · one-time setup needed"
      if (root.failing) return "Throttle · " + root.store.status.error
      if (root.paused) return "Throttle paused · right-click to resume"
      if (root.limiting) return "Throttle on · right-click to pause"
      return "Throttle · no limits"
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.store) root.store.toggleEnabled()
        return
      }
      root.toggle()
    }
  }
}
