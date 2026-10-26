import QtQuick
import qs.Commons
import qs.Ui
import "../vendor/yoyo-ui"
import "../model/format.js" as Format

// Traffic rows (live rates or byte totals) and "+ Add" candidates.
CursorSurface {
  id: root

  property string name: ""
  property real down: 0
  property real up: 0
  property int conns: 0
  property real peak: 1
  property int capDown: 0
  property int capUp: 0
  property string units: "mbit"
  // History rows show byte totals instead of rates.
  property bool bytes: false
  property bool muted: false
  property bool showBar: false
  // Optional chip on the right ("Add").
  property string actionText: ""
  property string actionTooltip: ""

  signal rowHovered()
  signal rowClicked()
  signal actionClicked()

  implicitHeight: Theme.dataRowHeight
  height: implicitHeight
  foreground: Theme.fg
  fill: Theme.hoverFill
  bordered: false

  RowHover {
    clickable: true
    pointer: false
    onHovered: root.rowHovered()
    onClicked: root.rowClicked()
  }

  // Share of the busiest row (history ranges), so the hog is obvious at a glance.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    radius: Style.cornerRadius
    width: parent.width * Math.min(1, (root.down + root.up) / Math.max(1, root.peak))
    // A few-pixel sliver reads as a stray edge line, not as a share.
    visible: root.showBar && width >= Math.max(radius * 2, Style.space(12))
    color: Theme.tint(Theme.accent, 0.10)
  }

  // Name keeps priority: the cap tags and "N conns" drop out first.
  Item {
    id: nameBox
    anchors.left: parent.left
    anchors.leftMargin: Theme.edge
    anchors.right: rates.left
    anchors.rightMargin: Theme.gap
    anchors.verticalCenter: parent.verticalCenter
    height: nameText.implicitHeight

    readonly property bool capped: root.capDown > 0 || root.capUp > 0
    readonly property bool extraFits: nameText.implicitWidth + extra.implicitWidth + Style.space(8) <= width

    Text {
      id: nameText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width)
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.name
      color: root.muted ? Theme.dim : Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.body
    }
    Row {
      id: extra
      visible: nameBox.extraFits && (nameBox.capped || root.conns > 1)
      anchors.left: nameText.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      CapTag { anchors.verticalCenter: parent.verticalCenter; arrow: "↓"; value: root.capDown; showOff: false }
      CapTag { anchors.verticalCenter: parent.verticalCenter; arrow: "↑"; value: root.capUp; showOff: false }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.conns > 1
        text: root.conns + " conns"
        color: Theme.faint
        font.family: Theme.fontFamily
        font.pixelSize: Theme.caption
      }
    }
  }

  Row {
    id: rates
    anchors.right: action.visible ? action.left : parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    Text {
      width: Style.space(86)
      horizontalAlignment: Text.AlignRight
      text: "↓ " + Format.formatAmount(root.down, root.bytes, root.units)
      color: root.down > 0 ? Theme.fg : Theme.faint
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
    Text {
      width: Style.space(86)
      horizontalAlignment: Text.AlignRight
      text: "↑ " + Format.formatAmount(root.up, root.bytes, root.units)
      color: root.up > 0 ? Theme.dim : Theme.faint
      font.family: Theme.fontFamily
      font.pixelSize: Theme.caption
    }
  }

  HeaderChip {
    id: action
    visible: root.actionText !== ""
    anchors.right: parent.right
    anchors.rightMargin: Theme.edge
    anchors.verticalCenter: parent.verticalCenter
    text: root.actionText
    on: root.hasCursor
    tooltipText: root.actionTooltip
    onClicked: root.actionClicked()
  }
}
