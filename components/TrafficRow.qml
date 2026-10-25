import qs.Commons as Commons
import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

CursorSurface {
  id: root

  property string name: ""
  property real down: 0
  property real up: 0
  property int conns: 0
  property real peak: 1
  property bool limited: false
  // Stats rows show byte totals instead of rates.
  property bool bytes: false
  property bool muted: false
  // Optional chip on the right ("Add" for candidate apps).
  property string actionText: ""
  property string actionTooltip: ""
  property color contentForeground: Commons.Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  signal rowHovered()
  signal actionClicked()

  implicitHeight: Style.space(40)
  height: implicitHeight
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Commons.Color.accent, Commons.Color.urgent)
  bordered: false

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
  }

  // Background bar: share of the busiest row, so the hog is obvious at a glance.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    radius: Style.cornerRadius
    width: parent.width * Math.min(1, (root.down + root.up) / Math.max(1, root.peak))
    color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.14)
    Behavior on width { NumberAnimation { duration: 250 } }
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: root.edgeMargin
    anchors.right: rates.left
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: root.name + (root.limited ? "  ·  limited" : "") + (root.conns > 1 ? "  ·  " + root.conns + " conns" : "")
    color: root.muted ? Qt.darker(root.contentForeground, 1.5) : root.contentForeground
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.body
  }

  Row {
    id: rates
    anchors.right: action.visible ? action.left : parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    Text {
      width: Style.space(96)
      horizontalAlignment: Text.AlignRight
      text: "↓ " + (root.bytes ? Model.formatBytes(root.down) : Model.formatRate(root.down))
      color: root.down > 0 ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      width: Style.space(96)
      horizontalAlignment: Text.AlignRight
      text: "↑ " + (root.bytes ? Model.formatBytes(root.up) : Model.formatRate(root.up))
      color: root.up > 0 ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }

  HeaderChip {
    id: action
    visible: root.actionText !== ""
    anchors.right: parent.right
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    text: root.actionText
    on: root.hasCursor
    contentForeground: root.contentForeground
    contentFontFamily: root.contentFontFamily
    tooltipText: root.actionTooltip
    onClicked: root.actionClicked()
  }
}
