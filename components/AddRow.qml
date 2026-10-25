import qs.Commons as Commons
import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// "Add an app" by process name (as in `ps -o comm`, up to 15 characters).
CursorSurface {
  id: root

  property var cfg: null
  property color contentForeground: Commons.Color.foreground
  property string contentFontFamily: Style.font.family
  property int edgeMargin: Style.space(6)

  readonly property string name: input.text.trim()
  readonly property string problem: {
    if (root.name === "") return ""
    if (!Model.validName(root.name)) return "Not allowed: letters, digits, space . _ + : -, no shells or system services"
    if (Model.knownProc(root.cfg, Model.procOf(root.name))) return "Already in the list"
    return ""
  }
  readonly property bool canSubmit: root.name !== "" && root.problem === ""

  signal rowHovered()
  signal submitted(string name)
  signal fieldFocusChanged(bool on)

  implicitHeight: col.implicitHeight + Style.space(14)
  height: implicitHeight
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Commons.Color.accent, Commons.Color.urgent)
  bordered: false

  function focusField() { input.forceActiveFocus() }
  function submit() {
    if (!root.canSubmit) return
    root.submitted(root.name)
    input.text = ""
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
  }

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.edgeMargin
    anchors.rightMargin: root.edgeMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Row {
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: input
        width: parent.width - addChip.width - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: "Process name, e.g. qbittorrent"
        maximumLength: 32
        foreground: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        hasCursor: root.hasCursor
        onAccepted: root.submit()
        onActiveFocusChanged: root.fieldFocusChanged(activeFocus)
        Keys.onEscapePressed: { input.text = ""; input.focus = false }
      }

      HeaderChip {
        id: addChip
        anchors.verticalCenter: parent.verticalCenter
        text: "Add"
        enabled: root.canSubmit
        on: root.canSubmit
        contentForeground: root.contentForeground
        contentFontFamily: root.contentFontFamily
        tooltipText: "Add this program to the Apps list (no cap until you set one)"
        onClicked: root.submit()
      }
    }

    Text {
      width: parent.width
      visible: root.problem !== ""
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.problem
      color: Commons.Color.urgent
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
