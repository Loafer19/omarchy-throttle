import qs.Commons as Commons
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar icon. Settings › Bar widget: "icon" (default), "dot" (a small urgent
// dot while a cap is maxed out, ≥ 90 %), "rate" (icon + live download).
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

  readonly property bool vertical: root.bar ? root.bar.vertical === true : false
  readonly property bool showRate: mode === "rate" && !vertical && store !== null && store.traffic !== null
  implicitWidth: button.implicitWidth + (showRate ? rateText.implicitWidth + Style.space(2) : 0)
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
  readonly property var cfg: store && store.cfg ? store.cfg : Model.DEFAULTS
  readonly property string mode: cfg.barWidget === "dot" || cfg.barWidget === "rate" ? cfg.barWidget : "icon"
  readonly property bool limiting: store ? store.limiting === true : false
  readonly property bool paused: store ? (store.cfg && store.cfg.enabled === false) : false
  readonly property bool failing: store && store.status ? (store.status.error || "") !== "" : false
  readonly property bool biting: limiting && store !== null && Model.biting(cfg, store.traffic)

  BarIconButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    bar: root.bar
    // nf-md-speedometer_slow while limiting, nf-md-speedometer otherwise.
    text: root.limiting ? "\uDB83\uDF86" : "\uDB81\uDCC5"
    active: root.limiting || root.failing
    activeColor: root.failing ? Commons.Color.urgent : Commons.Color.accent
    dimmed: root.paused
    tooltipText: root.store ? Model.tooltipText(root.cfg, root.store.status, root.store.traffic, root.limiting, root.cfg.units) : "Throttle"
    onPressed: function(b) { root.press(b) }

    // "dot" mode: a cap is maxed out right now.
    Rectangle {
      visible: root.mode === "dot" && root.biting && !root.paused
      width: Style.space(6)
      height: width
      radius: width / 2
      color: Commons.Color.urgent
      x: parent.width / 2 + Style.space(5)
      y: parent.height / 2 - Style.space(9)
    }
  }

  // "rate" mode: live download next to the icon (horizontal bars only).
  Text {
    id: rateText
    visible: root.showRate
    anchors.left: button.right
    anchors.leftMargin: -Style.space(4)
    anchors.verticalCenter: button.verticalCenter
    text: root.store && root.store.traffic && root.store.traffic.iface
      ? "↓" + Model.shortRate(root.store.traffic.iface.down, root.cfg.units) : ""
    color: root.failing ? Commons.Color.urgent : (root.bar ? root.bar.barForeground : Commons.Color.foreground)
    opacity: root.paused ? 0.5 : 1
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { root.press(mouse.button) }
    }
  }

  function press(b) {
    if (b === Qt.RightButton) {
      if (root.store) root.store.toggleEnabled()
      return
    }
    root.toggle()
  }
}
