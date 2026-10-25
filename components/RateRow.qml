import QtQuick
import qs.Commons
import qs.Ui
import "../theme"
import "../Model.js" as Model

// One cap: Off / steps / Custom chips; Custom opens a Mbit/s field inline,
// left of the chips, so the row keeps its height and the title stays put.
CursorSurface {
  id: root

  property string title: ""
  property int value: 0
  property var steps: Model.PRESETS

  // Custom stays open after the user picks it even if they type a step value.
  property bool customOpen: false
  readonly property string selectedKey: Model.rateKey(root.value, root.customOpen, root.steps)
  readonly property bool showField: root.selectedKey === "custom"

  signal rowHovered()
  signal valuePicked(int value)
  signal fieldFocusChanged(bool on)

  implicitHeight: Theme.rowHeight
  height: implicitHeight
  foreground: Theme.fg
  fill: Theme.hoverFill
  bordered: false

  function pick(key) {
    if (key === "custom") {
      root.customOpen = true
      if (root.value === 0) root.valuePicked(5)
      Qt.callLater(function() { numberField.field.forceActiveFocus() })
      return
    }
    root.customOpen = false
    root.valuePicked(Number(key))
  }

  // Keyboard h/l from the panel: step through the chips and leave Custom.
  function step(delta) {
    root.customOpen = false
    root.valuePicked(Model.stepPreset(root.value, delta, root.steps))
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
  }

  Column {
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.right: controls.left
    anchors.rightMargin: Theme.gap
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.title
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.body
      font.bold: true
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: Model.capDetail(root.value)
      color: Theme.dim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    NumberField {
      id: numberField
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showField
      label: ""
      value: root.value
      from: 1
      to: Model.MAX_MBIT
      stepSize: 1
      foreground: Theme.fg
      fontFamily: Theme.fontFamily
      fontSize: Theme.caption
      fieldWidth: Style.space(84)
      hasCursor: root.hasCursor && root.showField
      onModified: function(v) { root.valuePicked(v) }
      onHovered: function(on) { if (on) root.rowHovered() }
    }

    ChipRow {
      anchors.verticalCenter: parent.verticalCenter
      compact: true
      chips: Model.rateChips(root.steps)
      selectedKey: root.selectedKey
      onSelected: function(key) { root.pick(key) }
      onChipHovered: function(index) { root.rowHovered() }
    }
  }

  Connections {
    target: numberField.field
    function onActiveFocusChanged() { root.fieldFocusChanged(numberField.field.activeFocus) }
  }
}
