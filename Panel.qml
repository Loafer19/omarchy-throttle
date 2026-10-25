import qs.Commons as Commons
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components" as Throttle

Panel {
  id: root
  moduleName: "yoyo.throttle"
  ipcTarget: "yoyo.throttle"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dividerColor: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.12)
  readonly property int edgeMargin: Style.space(6)

  property var store: null
  property string activeTab: "limits"
  property bool fieldFocus: false

  readonly property var tabs: [
    { key: "limits", label: "Limits" },
    { key: "apps", label: "Apps" },
    { key: "traffic", label: "Traffic" },
    { key: "stats", label: "Stats" }
  ]

  readonly property var cfg: store && store.cfg ? store.cfg : Model.DEFAULTS
  readonly property var status: store ? store.status : null
  readonly property bool enabledOn: cfg.enabled !== false
  readonly property bool limiting: store ? store.limiting === true : false
  readonly property bool needsSetup: status !== null && status.helper !== "installed"

  readonly property var limitView: Model.limitRows(cfg)
  readonly property var appView: Model.appRows(cfg, status, store ? store.traffic : null)
  readonly property var emptyList: []
  readonly property var trafficView: store && store.traffic ? store.traffic.apps : emptyList

  property string statsRange: "week"
  readonly property var statsSummary: Model.statsSummary(store ? store.stats : null, statsRange)
  readonly property var statsView: Model.statsRows(statsSummary)
  readonly property real statsPeak: {
    var m = 1
    for (var i = 0; i < statsSummary.apps.length; i++) m = Math.max(m, statsSummary.apps[i].down + statsSummary.apps[i].up)
    return m
  }
  readonly property real trafficPeak: {
    var m = 1
    for (var i = 0; i < trafficView.length; i++) m = Math.max(m, trafficView[i].down + trafficView[i].up)
    return m
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

  // Live rates only while someone looks at Traffic (or Apps, for its "Add"
  // suggestions); the history is collected regardless, the tab just reads it.
  Binding {
    target: root.store
    property: "trafficWanted"
    value: root.opened && (root.activeTab === "traffic" || root.activeTab === "apps")
    when: root.store !== null
  }
  Binding {
    target: root.store
    property: "statsWanted"
    value: root.opened && root.activeTab === "stats"
    when: root.store !== null
  }

  function toggleEnabled() { if (store) store.toggleEnabled() }

  function setRate(row, mbit) {
    if (!store || !row) return
    if (row.app) store.setApp(row.app, row.field, Model.clampMbit(mbit))
    else store.setGlobal(row.field, mbit)
  }

  function toggleRow(row) {
    if (!store || !row || row.kind !== "toggle") return
    store.setApp(row.app, row.field, !row.checked)
  }

  function limitedName(name) { return Model.labelCapped(cfg, name) }

  function addApp(proc) { if (store) store.addApp(proc) }
  function removeApp(key) { if (store) store.removeApp(key) }

  function stepRange(dx) {
    var i = chipIndexByKey(Model.RANGES, statsRange) + dx
    statsRange = Model.RANGES[Math.max(0, Math.min(Model.RANGES.length - 1, i))].key
  }

  // ---- keyboard cursor (tabs → rows), same model as the other yoyo panels ----
  property bool cursorActive: false
  property string focusSection: "rows"
  property int selectedIndex: 0

  readonly property var activeRows: {
    if (activeTab === "limits") return limitView
    if (activeTab === "apps") return appView
    if (activeTab === "stats") return statsView
    return trafficView
  }

  function selectable(i) {
    var r = activeRows[i]
    if (!r) return false
    if (r.kind === "header") return r.removable === true
    return r.kind !== "section" && r.kind !== "note" && r.kind !== "chart"
  }
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
    activeTab = tabs[i].key
    setTabsCursor(i)
  }

  function rowItem(index) {
    var list = activeTab === "limits" ? limitList : (activeTab === "apps" ? appList
      : (activeTab === "stats" ? statsList : trafficList))
    var wrap = list.itemAtIndex ? list.itemAtIndex(index) : null
    return wrap ? wrap.row : null
  }

  function nudge(dx) {
    var r = activeRows[selectedIndex]
    if (!r) return
    if (r.kind === "rate") {
      var item = rowItem(selectedIndex)
      if (item && item.step) item.step(dx)
      else setRate(r, Model.stepPreset(r.value, dx))
    } else if (r.kind === "toggle") toggleRow(r)
    else if (r.kind === "range") stepRange(dx)
  }

  function moveCursor(dx, dy) {
    if (!ensureCursor()) return
    if (dy !== 0) {
      if (focusSection === "tabs") {
        if (dy > 0) { var f = firstSelectable(); if (f >= 0) setRowCursor(f) }
        return
      }
      var next = nextSelectable(selectedIndex, dy > 0 ? 1 : -1)
      if (next >= 0) selectedIndex = next
      else if (dy < 0) setTabsCursor(chipIndexByKey(tabs, activeTab))
      return
    }
    if (dx === 0) return
    if (focusSection === "tabs") {
      selectedIndex = Math.max(0, Math.min(tabs.length - 1, selectedIndex + dx))
      activeTab = tabs[selectedIndex].key
      return
    }
    nudge(dx)
  }

  function activateCursor() {
    if (!ensureCursor()) return
    if (focusSection === "tabs") { activeTab = tabs[selectedIndex].key; return }
    var r = activeRows[selectedIndex]
    var item = rowItem(selectedIndex)
    if (r && r.kind === "header") { if (item && item.activate) item.activate(); return }
    if (r && r.kind === "candidate") { addApp(r.proc); return }
    if (r && r.kind === "addfield") { if (item && item.focusField) item.focusField(); return }
    if (r && (r.kind === "stat" || r.kind === "range")) return
    nudge(1)
  }

  onActiveTabChanged: {
    focusSection = "rows"
    selectedIndex = Math.max(0, firstSelectable())
  }

  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    focusSection = "rows"
    selectedIndex = Math.max(0, firstSelectable())
    if (store) store.tick(false)
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
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.cycleTab(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onTextKey: function(text) { if (text === "p") root.toggleEnabled() }

      Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        Throttle.ChipRow {
          chips: root.tabs
          selectedKey: root.activeTab
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          cursorActive: root.cursorActive && root.focusSection === "tabs"
          cursorIndex: root.cursorActive && root.focusSection === "tabs" ? root.selectedIndex : -1
          onSelected: function(key) {
            root.activeTab = key
            root.setTabsCursor(root.chipIndexByKey(root.tabs, key))
          }
          onChipHovered: function(index) { root.setTabsCursor(index) }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.dividerColor }

        Item {
          width: parent.width
          height: Style.space(28)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: root.edgeMargin
            anchors.right: headerChips.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: Model.statusLine(root.status, root.cfg)
            color: root.status && root.status.error ? Commons.Color.urgent
              : (root.limiting ? root.contentForeground : Qt.darker(root.contentForeground, 1.5))
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            id: headerChips
            anchors.right: parent.right
            anchors.rightMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Throttle.HeaderChip {
              text: root.enabledOn ? "On" : "Paused"
              on: root.enabledOn
              enabled: !root.needsSetup
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              tooltipText: root.enabledOn ? "Pause every limit (p) — settings are kept" : "Resume limits (p)"
              onClicked: root.toggleEnabled()
            }
          }
        }

        // One-time setup card: the helper that touches tc/nft needs root once.
        Rectangle {
          width: parent.width
          visible: root.needsSetup
          height: visible ? setupCol.implicitHeight + Style.space(16) : 0
          radius: Style.cornerRadius
          color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
          border.width: Style.spacing.hairline
          border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.4)

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
              text: "One-time setup: shaping needs a tiny root helper. Run this once in a terminal (it installs the helper and a sudoers rule for it only):"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextEdit {
                width: parent.width - copyChip.width - Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                text: root.store ? root.store.installCommand : ""
                color: root.contentForeground
                font.family: "monospace"
                font.pixelSize: Style.font.caption
              }

              Throttle.HeaderChip {
                id: copyChip
                anchors.verticalCenter: parent.verticalCenter
                text: copied.running ? "Copied" : "Copy"
                contentForeground: root.contentForeground
                contentFontFamily: root.contentFontFamily
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

        Text {
          width: parent.width
          visible: root.activeTab === "traffic"
          leftPadding: root.edgeMargin
          rightPadding: root.edgeMargin
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: {
            var t = root.store ? root.store.traffic : null
            var head = (root.status && root.status.iface ? root.status.iface : "Network")
            if (!t || !t.iface) return head + " · measuring…"
            return head + "  ↓ " + Model.formatRate(t.iface.down) + "  ↑ " + Model.formatRate(t.iface.up)
              + "\nPer-app rows count TCP only; game UDP shows up in the total above."
          }
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.activeTab === "stats"
          leftPadding: root.edgeMargin
          rightPadding: root.edgeMargin
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: (root.status && root.status.iface ? root.status.iface : "Network")
            + "  ↓ " + Model.formatBytes(root.statsSummary.total.down)
            + "  ↑ " + Model.formatBytes(root.statsSummary.total.up)
            + "  · " + Model.rangeOf(root.statsRange).label.toLowerCase()
            + "\nApps count TCP payload; Other / UDP is the rest of the interface total (game UDP, DNS, headers)."
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        id: body
        anchors.top: header.bottom
        anchors.topMargin: root.edgeMargin
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        ListView {
          id: limitList
          anchors.fill: parent
          visible: root.activeTab === "limits"
          clip: true
          spacing: 0
          // Integer model: refreshed arrays update rows in place (no delegate reset,
          // so a focused Custom field keeps focus).
          model: root.limitView.length
          footer: Text {
            width: ListView.view ? ListView.view.width : 0
            topPadding: Style.space(12)
            leftPadding: root.edgeMargin
            rightPadding: root.edgeMargin
            wrapMode: Text.WordWrap
            text: "Set the cap a little under your real line speed so the queue stays on this PC (low ping) instead of in your router. Per-app caps (Heroic, Steam, or any other program) live in the Apps tab."
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
          delegate: Item {
            id: limitWrap
            required property int index
            readonly property var modelData: root.limitView[index] || ({})
            property alias row: limitRow
            width: ListView.view.width
            height: limitRow.height
            Throttle.RateRow {
              id: limitRow
              width: parent.width
              title: limitWrap.modelData.title || ""
              subtitle: Model.capLabel(limitWrap.modelData.value) + " · " + limitWrap.modelData.subtitle
              value: limitWrap.modelData.value || 0
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "limits" && root.selectedIndex === limitWrap.index
              onRowHovered: root.setRowCursor(limitWrap.index)
              onValuePicked: function(v) { root.setRate(limitWrap.modelData, v) }
              onFieldFocusChanged: function(on) { root.fieldFocus = on }
            }
          }
        }

        ListView {
          id: appList
          anchors.fill: parent
          visible: root.activeTab === "apps"
          clip: true
          spacing: 0
          model: root.appView.length
          delegate: Item {
            id: appWrap
            required property int index
            readonly property var modelData: root.appView[index] || ({})
            readonly property string kind: modelData.kind || ""
            readonly property bool cursorHere: root.cursorActive && root.focusSection === "rows" && root.activeTab === "apps" && root.selectedIndex === appWrap.index
            readonly property var row: kind === "rate" ? rateRow : (kind === "header" ? headerRow : (kind === "addfield" ? addRow : null))
            width: ListView.view.width
            height: kind === "header" || kind === "section" ? headerRow.height
              : kind === "rate" ? rateRow.height
              : kind === "toggle" ? toggleRow.height
              : kind === "candidate" ? candidateRow.height
              : kind === "addfield" ? addRow.height
              : noteText.implicitHeight

            Throttle.SectionRow {
              id: headerRow
              visible: appWrap.kind === "header" || appWrap.kind === "section"
              width: parent.width
              title: appWrap.modelData.title || ""
              subtitle: appWrap.modelData.subtitle || ""
              showDot: appWrap.kind === "header"
              removable: appWrap.modelData.removable === true
              running: Model.appStatus(root.status, appWrap.modelData.app).running === true
              limited: root.limiting && Model.appStatus(root.status, appWrap.modelData.app).cgroups.length > 0
                && Model.isCapped(Model.appCfg(root.cfg, appWrap.modelData.app))
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: appWrap.cursorHere && appWrap.kind === "header"
              onRowHovered: if (appWrap.modelData.removable === true) root.setRowCursor(appWrap.index)
              onRemoveClicked: root.removeApp(appWrap.modelData.app)
            }

            Throttle.RateRow {
              id: rateRow
              visible: appWrap.kind === "rate"
              width: parent.width
              title: appWrap.modelData.title || ""
              value: appWrap.modelData.value || 0
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: appWrap.cursorHere
              onRowHovered: root.setRowCursor(appWrap.index)
              onValuePicked: function(v) { root.setRate(appWrap.modelData, v) }
              onFieldFocusChanged: function(on) { root.fieldFocus = on }
            }

            Throttle.ToggleRow {
              id: toggleRow
              visible: appWrap.kind === "toggle"
              width: parent.width
              title: appWrap.modelData.title || ""
              subtitle: appWrap.modelData.subtitle || ""
              checked: appWrap.modelData.checked === true
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: appWrap.cursorHere
              onRowHovered: root.setRowCursor(appWrap.index)
              onRowClicked: {
                root.setRowCursor(appWrap.index)
                root.toggleRow(appWrap.modelData)
              }
            }

            Throttle.TrafficRow {
              id: candidateRow
              visible: appWrap.kind === "candidate"
              width: parent.width
              name: appWrap.modelData.title || ""
              down: appWrap.modelData.down || 0
              up: appWrap.modelData.up || 0
              conns: appWrap.modelData.conns || 0
              peak: root.trafficPeak
              actionText: "Add"
              actionTooltip: "Add " + (appWrap.modelData.title || "") + " to the Apps list (no cap until you set one)"
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: appWrap.cursorHere
              onRowHovered: root.setRowCursor(appWrap.index)
              onActionClicked: root.addApp(appWrap.modelData.proc)
            }

            Throttle.AddRow {
              id: addRow
              visible: appWrap.kind === "addfield"
              width: parent.width
              cfg: root.cfg
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: appWrap.cursorHere
              onRowHovered: root.setRowCursor(appWrap.index)
              onSubmitted: function(name) { root.addApp(name) }
              onFieldFocusChanged: function(on) { root.fieldFocus = on }
            }

            Text {
              id: noteText
              visible: appWrap.kind === "note"
              width: parent.width
              topPadding: Style.space(10)
              leftPadding: root.edgeMargin
              rightPadding: root.edgeMargin
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: appWrap.modelData.title || ""
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        ListView {
          id: trafficList
          anchors.fill: parent
          visible: root.activeTab === "traffic"
          clip: true
          spacing: Style.space(2)
          model: root.trafficView.length
          delegate: Item {
            id: trafficWrap
            required property int index
            readonly property var modelData: root.trafficView[index] || ({})
            property alias row: trafficRow
            width: ListView.view.width
            height: trafficRow.height
            Throttle.TrafficRow {
              id: trafficRow
              width: parent.width
              name: trafficWrap.modelData.name || ""
              down: trafficWrap.modelData.down || 0
              up: trafficWrap.modelData.up || 0
              conns: trafficWrap.modelData.conns || 0
              peak: root.trafficPeak
              limited: root.limiting && root.limitedName(trafficWrap.modelData.name)
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: root.cursorActive && root.focusSection === "rows" && root.activeTab === "traffic" && root.selectedIndex === trafficWrap.index
              onRowHovered: root.setRowCursor(trafficWrap.index)
            }
          }
        }

        ListView {
          id: statsList
          anchors.fill: parent
          visible: root.activeTab === "stats"
          clip: true
          spacing: Style.space(2)
          model: root.statsView.length
          footer: Text {
            width: ListView.view ? ListView.view.width : 0
            visible: root.statsSummary.apps.length === 0
            topPadding: Style.space(16)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.store && root.store.stats ? "Nothing counted in this range yet" : "Loading…"
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }
          delegate: Item {
            id: statWrap
            required property int index
            readonly property var modelData: root.statsView[index] || ({})
            readonly property string kind: modelData.kind || ""
            readonly property bool cursorHere: root.cursorActive && root.focusSection === "rows" && root.activeTab === "stats" && root.selectedIndex === statWrap.index
            readonly property var row: null
            width: ListView.view.width
            height: kind === "range" ? rangeChips.height + Style.space(6)
              : kind === "chart" ? chart.height + Style.space(6) : statRow.height

            Throttle.ChipRow {
              id: rangeChips
              visible: statWrap.kind === "range"
              x: root.edgeMargin
              chips: Model.RANGES
              selectedKey: root.statsRange
              compact: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              cursorActive: statWrap.cursorHere
              cursorIndex: statWrap.cursorHere ? root.chipIndexByKey(Model.RANGES, root.statsRange) : -1
              onSelected: function(key) { root.statsRange = key; root.setRowCursor(statWrap.index) }
              onChipHovered: function(index) { root.setRowCursor(statWrap.index) }
            }

            Throttle.StatsChart {
              id: chart
              visible: statWrap.kind === "chart"
              width: parent.width
              bars: root.statsSummary.bars
              peak: root.statsSummary.peak
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
            }

            Throttle.TrafficRow {
              id: statRow
              visible: statWrap.kind === "stat"
              width: parent.width
              name: statWrap.modelData.name || ""
              down: statWrap.modelData.down || 0
              up: statWrap.modelData.up || 0
              bytes: true
              muted: statWrap.modelData.other === true
              peak: root.statsPeak
              limited: root.limiting && root.limitedName(statWrap.modelData.name)
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              edgeMargin: root.edgeMargin
              hasCursor: statWrap.cursorHere
              onRowHovered: root.setRowCursor(statWrap.index)
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.activeTab === "traffic" && root.trafficView.length === 0
          text: root.store && root.store.traffic ? "No open TCP connections" : "Measuring…"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
