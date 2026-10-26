pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"

// One row of the panel's single ListView; the row's "kind" picks the
// component. Refreshed row arrays update rows in place (same kind → same
// component), so a focused Custom field keeps its focus.
Item {
  id: wrap

  required property int index
  property var panel: null
  readonly property var row: panel && panel.activeRows[index] ? panel.activeRows[index] : ({})
  readonly property string kind: row.kind || ""
  readonly property bool cursorHere: panel !== null && panel.cursorActive && panel.focusSection === "rows" && panel.selectedIndex === index
  readonly property var item: loader.item

  width: ListView.view ? ListView.view.width : 0
  height: loader.item ? (loader.item as Item).height : 0

  function hover() { if (wrap.panel) wrap.panel.setRowCursor(wrap.index) }

  Loader {
    id: loader
    width: parent.width
    sourceComponent: ({
      app: appComp, link: appComp, crumb: crumbComp, hero: heroComp, rate: rateComp, toggle: toggleComp,
      section: sectionComp, note: noteComp, empty: emptyComp, candidate: trafficComp, traffic: trafficComp,
      stat: trafficComp, addfield: addComp, total: totalComp, livechart: liveComp, daychart: dayComp,
      choice: choiceComp, action: actionComp
    })[wrap.kind] || null
  }

  Component {
    id: appComp
    AppRow {
      title: wrap.row.title || ""
      subtitle: wrap.row.subtitle || ""
      status: wrap.row.state || "idle"
      showDot: wrap.kind === "app"
      down: wrap.row.down || 0
      up: wrap.row.up || 0
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onRowClicked: wrap.panel.activateRow(wrap.index)
    }
  }
  Component {
    id: crumbComp
    CrumbRow {
      title: wrap.row.title || ""
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onRowClicked: wrap.panel.goBack()
    }
  }
  Component {
    id: heroComp
    HeroRow {
      title: wrap.row.title || ""
      subtitle: wrap.row.subtitle || ""
      status: wrap.row.state || "idle"
      trailing: wrap.row.trailing || ""
      removable: wrap.row.removable === true
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onRemoveClicked: wrap.panel.removeApp(wrap.row.app)
    }
  }
  Component {
    id: rateComp
    RateRow {
      title: wrap.row.title || ""
      value: wrap.row.value || 0
      steps: wrap.panel.steps
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onValuePicked: function(v) { wrap.panel.setRate(wrap.row, v) }
      onFieldFocusChanged: function(on) { wrap.panel.fieldFocus = on }
    }
  }
  Component {
    id: toggleComp
    ToggleRow {
      title: wrap.row.title || ""
      subtitle: wrap.row.subtitle || ""
      checked: wrap.row.checked === true
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onRowClicked: { wrap.hover(); wrap.panel.toggleRow(wrap.row) }
    }
  }
  Component {
    id: sectionComp
    SectionHeader { title: wrap.row.title || ""; caption: wrap.row.caption || "" }
  }
  Component {
    id: noteComp
    Text {
      topPadding: Style.space(6)
      bottomPadding: Style.space(6)
      leftPadding: Theme.edge
      rightPadding: Theme.edge
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: wrap.row.title || ""
      color: Theme.faint
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }
  Component {
    id: emptyComp
    EmptyState { title: wrap.row.title || ""; subtitle: wrap.row.subtitle || "" }
  }
  Component {
    id: trafficComp
    TrafficRow {
      readonly property bool candidate: wrap.kind === "candidate"
      name: (candidate ? wrap.row.title : wrap.row.name) || ""
      down: wrap.row.down || 0
      up: wrap.row.up || 0
      conns: wrap.row.conns || 0
      capDown: wrap.row.capDown || 0
      capUp: wrap.row.capUp || 0
      units: wrap.panel.units
      bytes: wrap.kind === "stat"
      muted: wrap.row.other === true
      showBar: wrap.kind === "stat"
      peak: wrap.kind === "stat" ? wrap.panel.statsPeak : 1
      actionText: candidate || wrap.row.addable === true ? "Add" : ""
      actionTooltip: "Add " + name + " to Limits (no cap until you set one)"
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onRowClicked: wrap.panel.activateRow(wrap.index)
      onActionClicked: wrap.panel.addAndOpen(wrap.row.proc, candidate ? wrap.row.title : wrap.row.name)
    }
  }
  Component {
    id: addComp
    AddRow {
      cfg: wrap.panel.cfg
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onSubmitted: function(name) { wrap.panel.addAndOpen(name, "") }
      onFieldFocusChanged: function(on) { wrap.panel.fieldFocus = on }
    }
  }
  Component {
    id: totalComp
    TotalRow {
      down: wrap.row.down || 0
      up: wrap.row.up || 0
      bytes: wrap.row.bytes === true
      measuring: wrap.row.measuring === true
      units: wrap.panel.units
      caption: wrap.row.caption || ""
    }
  }
  Component {
    id: liveComp
    LiveChart { series: wrap.panel.liveSeries; units: wrap.panel.units }
  }
  Component {
    id: dayComp
    StatsChart { bars: wrap.panel.statsSummary.bars; peak: wrap.panel.statsSummary.peak }
  }
  Component {
    id: choiceComp
    ChoiceRow {
      title: wrap.row.title || ""
      subtitle: wrap.row.subtitle || ""
      options: wrap.row.options || []
      value: wrap.row.value || ""
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onPicked: function(key) { wrap.hover(); wrap.panel.applyChoice(wrap.row, key) }
    }
  }
  Component {
    id: actionComp
    ActionRow {
      title: wrap.row.title || ""
      subtitle: wrap.row.subtitle || ""
      actionLabel: wrap.row.chip || ""
      confirm: wrap.row.confirm === true
      doneText: confirm ? "Cleared" : "Copied"
      hasCursor: wrap.cursorHere
      onRowHovered: wrap.hover()
      onTriggered: wrap.panel.runAction(wrap.row)
    }
  }
}
