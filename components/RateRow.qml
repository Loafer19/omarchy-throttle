import qs.Commons as Commons
import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// One cap: preset chips (Off/10/25/50/100/Custom) and a Mbit/s field for Custom.
CursorSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property int value: 0
  property color contentForeground: Commons.Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  // Custom stays open after the user picks it even if they type a preset value.
  property bool customOpen: false
  readonly property string selectedKey: Model.rateKey(root.value, root.customOpen)
  readonly property bool showField: root.selectedKey === "custom"

  signal rowHovered()
  signal valuePicked(int value)
  signal fieldFocusChanged(bool on)

  implicitHeight: Math.max(Style.space(52), Math.max(infoCol.implicitHeight, controls.implicitHeight) + Style.space(14))
  height: implicitHeight
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Commons.Color.accent, Commons.Color.urgent)
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

  // Keyboard h/l from the panel: step presets and leave Custom.
  function step(delta) {
    root.customOpen = false
    root.valuePicked(Model.stepPreset(root.value, delta))
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
  }

  Column {
    id: infoCol
    anchors.left: parent.left
    anchors.leftMargin: root.edgeMargin
    anchors.right: controls.left
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.title
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.subtitle !== "" ? root.subtitle : Model.capLabel(root.value)
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Column {
    id: controls
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    ChipRow {
      id: chips
      anchors.right: parent.right
      compact: true
      chips: Model.rateChips()
      selectedKey: root.selectedKey
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
      onSelected: function(key) { root.pick(key) }
      onChipHovered: function(index) { root.rowHovered() }
    }

    Row {
      anchors.right: parent.right
      visible: root.showField
      spacing: Style.space(6)

      NumberField {
        id: numberField
        label: ""
        value: root.value
        from: 1
        to: Model.MAX_MBIT
        stepSize: 1
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        fieldWidth: Style.space(96)
        hasCursor: root.hasCursor && root.showField
        onModified: function(v) { root.valuePicked(v) }
        onHovered: function(on) { if (on) root.rowHovered() }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Mbit/s"
        color: Qt.darker(root.contentForeground, 1.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Connections {
    target: numberField.field
    function onActiveFocusChanged() { root.fieldFocusChanged(numberField.field.activeFocus) }
  }
}
