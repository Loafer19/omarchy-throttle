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
  readonly property real statsPeak: {
    var m = 1
    for (var i = 0; i < statsSummary.apps.length; i++) m = Math.max(m, statsSummary.apps[i].down + statsSummary.apps[i].up)
    return m
  }

  readonly property var activeRows: {
    if (activeTab === "limits") {
      if (limitsSub === "connection") return Views.connectionRows(cfg, status)
      if (limitsSub === "add") return Views.addRows(cfg, traffic)
      if (detailKey !== "") {
        var d = Views.detailRows(cfg, status, traffic, detailKey, limiting, units)
        if (d.length) return d
      }
      return Views.appListRows(cfg, status, traffic, limiting, units)
    }
    if (activeTab === "traffic") {
      if (trafficSub === "live") return Views.liveRows(cfg, traffic, store && store.history ? store.history : emptyList)
      return Views.historyRows(cfg, statsSummary, !!(store && store.stats))
    }
    return Settings.settingsRows(cfg, status, !needsSetup)
  }
  readonly property bool inDetail: activeTab === "limits" && limitsSub === "apps" && detailKey !== "" && activeRows.length > 0 && activeRows[0].kind === "crumb"

  readonly property string subCaption: {
    if (activeTab === "limits") return Apps.appList(cfg).length + " of " + Apps.MAX_APPS + " apps"
    if (activeTab === "traffic") return (status && status.iface ? status.iface : "network") + (trafficSub === "live" ? " · every 1.5 s" : "")
    return ""
  }

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
    setRowCursor(Math.max(0, nextSelectable(1, 1)))
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

  function selectable(i) { return Views.selectableRow(activeRows[i]) }
  function firstSelectable() {
    for (var i = 0; i < activeRows.length; i++) if (selectable(i)) return i
    return -1
  }
  function nextSelectable(from, dir) {
    for (var i = from + dir; i >= 0 && i < activeRows.length; i += dir) if (selectable(i)) return i
    return -1
  }

  function chipIndexByKey(chips, key) {
    for (var i = 0; i < chips.length; i++) if (String(chips[i].key) === String(key)) return i
    return 0
  }

  function setRowCursor(index) {
    cursorActive = true
    focusSection = "rows"
    selectedIndex = index
  }
  function setTabsCursor(index) {
    cursorActive = true
    focusSection = "tabs"
    selectedIndex = index
  }
  function setFiltersCursor(index) {
    cursorActive = true
    focusSection = "filters"
    selectedIndex = index
  }

  function ensureCursor() {
    if (cursorActive) return true
    cursorActive = true
    var first = firstSelectable()
    if (first >= 0) { focusSection = "rows"; selectedIndex = first }
    else { focusSection = "tabs"; selectedIndex = chipIndexByKey(tabs, activeTab) }
    return false
  }

  function cycleTab(direction) {
    var n = tabs.length
    var i = (chipIndexByKey(tabs, activeTab) + direction) % n
    if (i < 0) i += n
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
    var hasFilters = subtabs.length > 0
    if (dy !== 0) {
      if (focusSection === "tabs") {
        if (dy < 0) return
        if (hasFilters) { setFiltersCursor(chipIndexByKey(subtabs, activeSub)); return }
        var f = firstSelectable(); if (f >= 0) setRowCursor(f)
        return
      }
      if (focusSection === "filters") {
        if (dy < 0) { setTabsCursor(chipIndexByKey(tabs, activeTab)); return }
        var g = firstSelectable(); if (g >= 0) setRowCursor(g)
        return
      }
      var next = nextSelectable(selectedIndex, dy > 0 ? 1 : -1)
      if (next >= 0) { selectedIndex = next; positionActiveList() }
      else if (dy < 0) {
        list.positionViewAtBeginning()
        if (hasFilters) setFiltersCursor(chipIndexByKey(subtabs, activeSub))
        else setTabsCursor(chipIndexByKey(tabs, activeTab))
      }
      return
    }
    if (dx === 0) return
    if (focusSection === "tabs") {
      var t = Math.max(0, Math.min(tabs.length - 1, selectedIndex + dx))
      setTab(tabs[t].key)
      setTabsCursor(t)
      return
    }
    if (focusSection === "filters") {
      var s = Math.max(0, Math.min(subtabs.length - 1, selectedIndex + dx))
      setSub(subtabs[s].key)
      setFiltersCursor(s)
      return
    }
    nudge(dx)
  }

  function activateRow(index) {
    var r = activeRows[index]
    if (!r) return
    setRowCursor(index)
    var item = rowItem(index)
    if (r.kind === "app") openApp(r.app)
    else if (r.kind === "link") { setSub(r.target); setFiltersCursor(chipIndexByKey(subtabs, r.target)) }
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
    if (focusSection === "rows") selectedIndex = Math.max(0, firstSelectable())
    list.positionViewAtBeginning()
  }
  onActiveTabChanged: { detailKey = ""; resetRowCursor() }
  onLimitsSubChanged: resetRowCursor()
  onTrafficSubChanged: resetRowCursor()

  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    focusSection = "rows"
    selectedIndex = Math.max(0, firstSelectable())
    if (store) store.tick(false)
  }

  readonly property var keyHints: {
    if (focusSection === "filters" && cursorActive) return [["h l", activeTab === "traffic" ? "range" : "sub-tabs"], ["j", "rows"], ["Tab", "tabs"], ["p", "pause"]]
    if (inDetail) return [["Esc", "back"], ["j k", "rows"], ["h l", "change"], ["Enter", "toggle"], ["p", "pause"]]
    if (activeTab === "settings") return [["Tab", "tabs"], ["j k", "rows"], ["h l", "change"], ["Enter", "next"], ["p", "pause"]]
    if (activeTab === "traffic") return [["Tab", "tabs"], ["h l", "range"], ["j k", "rows"], ["Enter", "open · add"], ["p", "pause"]]
    if (limitsSub === "connection") return [["Tab", "tabs"], ["j k", "rows"], ["h l", "change"], ["p", "pause"]]
    if (limitsSub === "add") return [["Tab", "tabs"], ["j k", "rows"], ["Enter", "add"], ["p", "pause"]]
    return [["Tab", "tabs"], ["h l", "sub-tabs"], ["j k", "rows"], ["Enter", "open"], ["p", "pause"]]
  }

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
            root.setTabsCursor(root.chipIndexByKey(root.tabs, key))
          }
          onChipHovered: function(index) { root.setTabsCursor(index) }
        }

        PanelSeparator { foreground: Theme.fg }

        Item {
          width: parent.width
          height: Style.space(24)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.edge
            anchors.right: onChip.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: Status.statusLine(root.status, root.cfg)
            color: root.status && root.status.error ? Theme.urgent : (root.limiting ? Theme.fg : Theme.dim)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.caption
          }

          HeaderChip {
            id: onChip
            anchors.right: parent.right
            anchors.rightMargin: Theme.edge
            anchors.verticalCenter: parent.verticalCenter
            text: root.enabledOn ? "On" : "Paused"
            on: root.enabledOn
            enabled: !root.needsSetup
            tooltipText: root.enabledOn ? "Pause every limit (p) — settings are kept" : "Resume limits (p)"
            onClicked: root.toggleEnabled()
          }
        }

        // One-time setup card: the helper that touches tc/nft needs root once.
        Rectangle {
          width: parent.width
          visible: root.needsSetup
          height: visible ? setupCol.implicitHeight + Style.space(16) : 0
          radius: Style.cornerRadius
          color: Theme.tint(Theme.accent, 0.12)
          border.width: Style.space(1)
          border.color: Theme.tint(Theme.accent, 0.4)

          Column {
            id: setupCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "One-time setup: shaping needs a tiny root helper. Run this once in a terminal:"
              color: Theme.fg
              font.family: Theme.fontFamily
              font.pixelSize: Theme.caption
            }

            Row {
              width: parent.width
              spacing: Theme.gap

              TextEdit {
                width: parent.width - copyChip.width - Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                text: root.store ? root.store.installCommand : ""
                color: Theme.fg
                font.family: "monospace"
                font.pixelSize: Theme.caption
              }

              HeaderChip {
                id: copyChip
                anchors.verticalCenter: parent.verticalCenter
                text: copied.running ? "Copied" : "Copy"
                tooltipText: "Copy the command to the clipboard"
                onClicked: {
                  if (root.store) root.store.copyInstallCommand()
                  copied.restart()
                }
                Timer { id: copied; interval: 1500 }
              }
            }
          }
        }

        // Second level: sub-tabs (the "filters" cursor section) and a caption.
        Item {
          width: parent.width
          visible: root.subtabs.length > 0
          height: visible ? Style.space(24) : 0

          ChipRow {
            id: subChips
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            compact: true
            chips: root.subtabs
            selectedKey: root.activeSub
            cursorActive: root.cursorActive && root.focusSection === "filters"
            cursorIndex: root.cursorActive && root.focusSection === "filters" ? root.selectedIndex : -1
            onSelected: function(key) {
              root.setSub(key)
              root.setFiltersCursor(root.chipIndexByKey(root.subtabs, key))
            }
            onChipHovered: function(index) { root.setFiltersCursor(index) }
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.edge
            anchors.left: subChips.right
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: root.subCaption
            color: Theme.faint
            font.family: Theme.fontFamily
            font.pixelSize: Theme.caption
          }
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
