pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "defaults.js" as Defaults
import "model/format.js" as Format
import "model/rates.js" as Rates
import "model/apps.js" as Apps
import "model/live.js" as Live
import "model/stats.js" as Stats
import "model/views.js" as Views
import "model/settings.js" as Settings
import "model/status.js" as Status
import "model/nav.js" as Nav
import "vendor/yoyo-ui"
import "components" as Throttle

// Two-level tabs: Limits (Apps · Connection · + Add), Traffic (Live · Today ·
// 7 days · 30 days), Settings. Keyboard: Tab cycles tabs; j/k walk
// tabs → sub-tabs → rows; h/l switch sub-tabs or change the row's value;
// Enter opens / toggles; Esc goes back from an app, then closes; p pauses.
Panel {
  id: root
  moduleName: "yoyo.throttle"
  ipcTarget: "yoyo.throttle"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Theme.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  Binding { target: Theme; property: "foreground"; value: root.contentForeground }
  Binding { target: Theme; property: "fontFamily"; value: root.contentFontFamily }

  property var store: null
  property string activeTab: "limits"
  property string limitsSub: "apps"
  property string trafficSub: "live"
  // Limits › Apps drill-in: the app key whose detail page is open, or "".
  property string detailKey: ""
  property bool fieldFocus: false

  readonly property var tabs: Views.TABS
  readonly property var subtabs: Views.subtabsOf(activeTab)
  readonly property string activeSub: activeTab === "limits" ? limitsSub : (activeTab === "traffic" ? trafficSub : "")

  readonly property var emptyList: []
  readonly property var cfg: store && store.cfg ? store.cfg : Defaults.CONFIG
  readonly property var status: store ? store.status : null
  readonly property var traffic: store ? store.traffic : null
  readonly property bool enabledOn: cfg.enabled !== false
  readonly property bool limiting: store ? store.limiting === true : false
  readonly property bool needsSetup: status !== null && status.helper !== "installed"
  readonly property string units: cfg.units === "mbyte" ? "mbyte" : "mbit"
  readonly property var steps: Rates.stepsOf(cfg)

  readonly property var liveSeries: Live.liveSeries(store && store.history ? store.history : emptyList, 4, units)
  readonly property var statsSummary: Stats.statsSummary(store ? store.stats : null, trafficSub === "live" ? "today" : trafficSub)
  readonly property real statsPeak: Stats.peakOf(statsSummary)

  readonly property var activeRows: Views.rowsFor({
    tab: activeTab, limitsSub: limitsSub, trafficSub: trafficSub, detailKey: detailKey,
    cfg: cfg, status: status, traffic: traffic, history: store && store.history ? store.history : emptyList,
    stats: store ? store.stats : null, summary: statsSummary, limiting: limiting, units: units, needsSetup: needsSetup
  })
  readonly property bool inDetail: activeTab === "limits" && limitsSub === "apps" && detailKey !== "" && activeRows.length > 0 && activeRows[0].kind === "crumb"

  readonly property string subCaption: Views.subCaption(activeTab, trafficSub, cfg, status)

  function bindStore() {
    if (store) return
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return
    var s = host.serviceFor("yoyo.throttle")
    if (s) store = s
  }

  onBarChanged: bindStore()
  Component.onCompleted: bindStore()

  Timer {
    interval: 200
    running: root.store === null
    repeat: true
    onTriggered: root.bindStore()
  }

  // Live rates while Limits (live "now" rates, + Add suggestions) or
  // Traffic › Live is open; the per-day history is collected regardless.
  Binding {
    target: root.store
    property: "trafficWanted"
    value: root.opened && (root.activeTab === "limits" || (root.activeTab === "traffic" && root.trafficSub === "live"))
    when: root.store !== null
  }
  Binding {
    target: root.store
    property: "statsWanted"
    value: root.opened && root.activeTab === "traffic" && root.trafficSub !== "live"
    when: root.store !== null
  }

  // ---------------------------------------------------------- actions ---
  function toggleEnabled() { if (store) store.toggleEnabled() }

  function setRate(row, mbit) {
    if (!store || !row) return
    if (row.app) store.setApp(row.app, row.field, Format.clampMbit(mbit))
    else store.setGlobal(row.field, mbit)
  }

  function toggleRow(row) {
    if (!store || !row || row.kind !== "toggle") return
    store.setApp(row.app, row.field, !row.checked)
  }

  function applyChoice(row, key) {
    if (!store || !row) return
    var p = Settings.settingPatch(cfg, row.setting, key)
    if (p) store.setPatch(p)
  }

  function runAction(row) {
    if (!store || !row) return
    if (row.action === "clear-history") store.resetStats()
    else if (row.action === "copy-install") store.copyInstallCommand()
    else if (row.action === "copy-uninstall") store.copyUninstallCommand()
  }

  function removeApp(key) {
    if (!store) return
    store.removeApp(key)
    goBack()
  }

  // Add a program and open its page, so the next keystroke sets its cap.
  function addAndOpen(proc, label) {
    if (!store) return
    var p = Apps.addPatch(cfg, proc, label)
    if (!p) return
    var key = Object.keys(p.apps)[0]
    if (store.addApp(proc, label) !== false) openApp(key)
  }

  function setTab(key) {
    if (activeTab === key) return
    activeTab = key
  }
  function setSub(key) {
    if (activeTab === "limits") { limitsSub = key; detailKey = "" }
    else if (activeTab === "traffic") trafficSub = key
  }

  function openApp(key) {
    activeTab = "limits"
    limitsSub = "apps"
    detailKey = key
    // Land on Download (row 2) so h/l sets the cap right away.
    setRowCursor(Math.max(0, Nav.nextSelectable(activeRows, 1, 1)))
    list.positionViewAtBeginning()
  }

  function goBack() {
    if (detailKey === "") return false
    var key = detailKey
    detailKey = ""
    var idx = 0
    for (var i = 0; i < activeRows.length; i++) if (activeRows[i].app === key) idx = i
    setRowCursor(idx)
    positionActiveList()
    return true
  }

  // ---- keyboard cursor: tabs → filters (sub-tabs) → rows, as System Tidy ----
  property bool cursorActive: false
  property string focusSection: "rows"
  property int selectedIndex: 0

  function setCursor(section, index) {
    cursorActive = true
    focusSection = section
    selectedIndex = index
  }
  function setRowCursor(index) { setCursor("rows", index) }
  function setTabsCursor(index) { setCursor("tabs", index) }
  function setFiltersCursor(index) { setCursor("filters", index) }
  // Cursor on the active chip of a chip section.
  function chipCursor(section) {
    if (section === "tabs") setTabsCursor(Nav.chipIndex(tabs, activeTab))
    else setFiltersCursor(Nav.chipIndex(subtabs, activeSub))
  }

  // The first key press only shows the cursor (false); later ones act.
  function ensureCursor() {
    if (cursorActive) return true
    var first = Nav.firstSelectable(activeRows)
    if (first >= 0) setRowCursor(first)
    else chipCursor("tabs")
    return false
  }

  function cycleTab(direction) {
    var i = Nav.cycleIndex(Nav.chipIndex(tabs, activeTab), direction, tabs.length)
    setTab(tabs[i].key)
    setTabsCursor(i)
  }

  function rowItem(index) {
    var wrap = list.itemAtIndex ? list.itemAtIndex(index) as Throttle.RowDelegate : null
    return wrap ? wrap.item : null
  }

  function positionActiveList() {
    if (focusSection === "rows" && selectedIndex >= 0) list.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function nudge(dx) {
    var r = activeRows[selectedIndex]
    if (!r) return
    if (r.kind === "rate") {
      var item = rowItem(selectedIndex)
      if (item && item.step) item.step(dx)
      else setRate(r, Rates.stepPreset(r.value, dx, steps))
    } else if (r.kind === "toggle") toggleRow(r)
    else if (r.kind === "choice") applyChoice(r, Settings.stepChoice(r, dx, false))
  }

  function moveCursor(dx, dy) {
    if (!ensureCursor()) return
    if (dy !== 0) {
      var to = Nav.verticalTarget(focusSection, selectedIndex, activeRows, subtabs.length > 0, dy)
      if (!to) return
      if (to.top) list.positionViewAtBeginning()
      if (to.section !== "rows") chipCursor(to.section)
      else { setRowCursor(to.index); positionActiveList() }
      return
    }
    if (dx === 0) return
    if (focusSection === "tabs") {
      var t = Nav.clampIndex(selectedIndex + dx, tabs.length)
      setTab(tabs[t].key)
      setTabsCursor(t)
    } else if (focusSection === "filters") {
      var s = Nav.clampIndex(selectedIndex + dx, subtabs.length)
      setSub(subtabs[s].key)
      setFiltersCursor(s)
    } else nudge(dx)
  }

  function activateRow(index) {
    var r = activeRows[index]
    if (!r) return
    setRowCursor(index)
    var item = rowItem(index)
    if (r.kind === "app") openApp(r.app)
    else if (r.kind === "link") { setSub(r.target); chipCursor("filters") }
    else if (r.kind === "crumb") goBack()
    else if (r.kind === "hero") { if (item && item.activate) item.activate() }
    else if (r.kind === "rate") nudge(1)
    else if (r.kind === "toggle") toggleRow(r)
    else if (r.kind === "candidate") addAndOpen(r.proc, r.title)
    else if (r.kind === "addfield") { if (item && item.focusField) item.focusField() }
    else if (r.kind === "traffic" || r.kind === "stat") {
      if (r.key) openApp(r.key)
      else if (r.addable) addAndOpen(r.proc, r.name)
    }
    else if (r.kind === "choice") applyChoice(r, Settings.stepChoice(r, 1, true))
    else if (r.kind === "action") { if (item && item.activate) item.activate() }
  }

  function activateCursor() {
    if (!ensureCursor()) return
    if (focusSection === "tabs") { setTab(tabs[selectedIndex].key); return }
    if (focusSection === "filters") { setSub(subtabs[selectedIndex].key); return }
    activateRow(selectedIndex)
  }

  function backOrClose() {
    if (goBack()) return
    root.close()
  }

  function resetRowCursor() {
    if (focusSection === "rows") selectedIndex = Math.max(0, Nav.firstSelectable(activeRows))
    list.positionViewAtBeginning()
  }
  onActiveTabChanged: { detailKey = ""; resetRowCursor() }
  onLimitsSubChanged: resetRowCursor()
  onTrafficSubChanged: resetRowCursor()

  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    focusSection = "rows"
    selectedIndex = Math.max(0, Nav.firstSelectable(activeRows))
    if (store) store.tick(false)
  }

  readonly property var keyHints: Nav.keyHints({ section: focusSection, cursorActive: cursorActive, inDetail: inDetail, tab: activeTab, limitsSub: limitsSub })

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.fieldFocus
      onCloseRequested: root.backOrClose()
      onTabRequested: function(direction) { root.cycleTab(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onTextKey: function(text) { if (text === "p") root.toggleEnabled() }

      Column {
        id: headerBox
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        ChipRow {
          chips: root.tabs
          selectedKey: root.activeTab
          cursorActive: root.cursorActive && root.focusSection === "tabs"
          cursorIndex: root.cursorActive && root.focusSection === "tabs" ? root.selectedIndex : -1
          onSelected: function(key) {
            root.setTab(key)
            root.setTabsCursor(Nav.chipIndex(root.tabs, key))
          }
          onChipHovered: function(index) { root.setTabsCursor(index) }
        }

        PanelSeparator { foreground: Theme.fg }

        Throttle.StatusHeader {
          text: Status.statusLine(root.status, root.cfg)
          textColor: root.status && root.status.error ? Theme.urgent : (root.limiting ? Theme.fg : Theme.dim)
          on: root.enabledOn
          canToggle: !root.needsSetup
          onToggleRequested: root.toggleEnabled()
        }

        Throttle.SetupCard {
          visible: root.needsSetup
          command: root.store ? root.store.installCommand : ""
          onCopyRequested: if (root.store) root.store.copyInstallCommand()
        }

        Throttle.SubTabBar {
          chips: root.subtabs
          selectedKey: root.activeSub
          cursorIndex: root.cursorActive && root.focusSection === "filters" ? root.selectedIndex : -1
          caption: root.subCaption
          onSelected: function(key) {
            root.setSub(key)
            root.setFiltersCursor(Nav.chipIndex(root.subtabs, key))
          }
          onChipHovered: function(index) { root.setFiltersCursor(index) }
        }
      }

      ListView {
        id: list
        anchors.top: headerBox.bottom
        anchors.topMargin: Theme.edge
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footerHints.top
        anchors.bottomMargin: Style.space(4)
        clip: true
        spacing: 0
        boundsBehavior: Flickable.StopAtBounds
        model: root.activeRows.length
        delegate: Throttle.RowDelegate { panel: root }
      }

      PanelSeparator {
        anchors.bottom: footerHints.top
        anchors.bottomMargin: Style.space(4)
        foreground: Theme.fg
        strength: 0.08
      }

      KeyHints {
        id: footerHints
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: Theme.edge
        height: Style.space(16)
        hints: root.keyHints
      }
    }
  }
}
