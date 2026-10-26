import QtQuick
import qs.Commons
import "../vendor/yoyo-ui"

// Second level under the tabs: the sub-tab chips (the "filters" cursor
// section) and a right-aligned caption ("3 of 8 apps").
Item {
  id: root

  property var chips: []
  property string selectedKey: ""
  property int cursorIndex: -1
  property string caption: ""
  signal selected(string key)
  signal chipHovered(int index)

  width: parent ? parent.width : 0
  visible: chips.length > 0
  height: visible ? Style.space(24) : 0

  ChipRow {
    id: subChips
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    compact: true
    chips: root.chips
    selectedKey: root.selectedKey
    cursorActive: root.cursorIndex >= 0
    cursorIndex: root.cursorIndex
    onSelected: function(key) { root.selected(key) }
    onChipHovered: function(index) { root.chipHovered(index) }
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.left: subChips.right
    anchors.leftMargin: Theme.gap
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    text: root.caption
    color: Theme.faint
    font.family: Theme.fontFamily
    font.pixelSize: Theme.caption
  }
}
