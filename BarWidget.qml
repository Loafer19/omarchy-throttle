import qs.Commons as Commons
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "vendor/yoyo-ui"
import "defaults.js" as Defaults
import "model/format.js" as Format
import "model/status.js" as Status

// Bar icon. Settings › Bar widget: "icon" (default), "dot" (a small urgent
// dot while a cap is maxed out, ≥ 90 %), "rate" (icon + live download).
BarWidget {
  id: root
  moduleName: "yoyo.throttle"

  // The panel is loaded by URL, so it is untyped here (var) on purpose.
  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  function injectPanel() {
    var target = root.panelItem
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Host objects typed QtObject in the base / Style; read them untyped.
  readonly property var host: root.bar
  readonly property var barStyle: Style.bar
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

  readonly property var store: panelItem ? panelItem.store : null
  readonly property var cfg: store && store.cfg ? store.cfg : Defaults.CONFIG
  readonly property string mode: cfg.barWidget === "dot" || cfg.barWidget === "rate" ? cfg.barWidget : "icon"
  readonly property bool limiting: store ? store.limiting === true : false
  readonly property bool paused: store ? (store.cfg && store.cfg.enabled === false) : false
  readonly property bool failing: store && store.status ? (store.status.error || "") !== "" : false
  readonly property bool biting: limiting && store !== null && Status.biting(cfg, store.traffic)

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
    tooltipText: root.store ? Status.tooltipText(root.cfg, root.store.status, root.store.traffic, root.limiting, root.cfg.units) : "Throttle"
    onPressed: function(b) { root.press(b) }

    // "dot" mode: a cap is maxed out right now. A small badge just outside
    // the glyph's top-right corner (same on horizontal and vertical bars).
    Rectangle {
      id: badge
      readonly property real glyphHalf: Math.max(button.glyphPaintedWidth, root.barStyle.iconCanvas * 0.75) / 2
      visible: root.mode === "dot" && root.biting && !root.paused
      width: Math.max(4, Math.round(root.barStyle.iconCanvas * 0.32))
      height: width
      radius: width / 2
      color: Commons.Color.urgent
      x: Math.min(parent.width - width, Math.round(parent.width / 2 + glyphHalf - 1))
      y: Math.max(0, Math.round(parent.height / 2 - root.barStyle.iconCanvas / 2 - height / 2 + 1))
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
      ? "↓" + Format.shortRate(root.store.traffic.iface.down, root.cfg.units) : ""
    color: root.failing ? Commons.Color.urgent : (root.host ? root.host.barForeground : Commons.Color.foreground)
    opacity: root.paused ? 0.5 : 1
    font.family: root.host ? root.host.fontFamily : Style.fontFamily
    font.pixelSize: Theme.caption
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
