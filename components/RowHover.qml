import QtQuick

// Fills a row: hovering moves the keyboard cursor onto it (hovered()), and
// clickable rows take left clicks with a pointing-hand cursor.
MouseArea {
  property bool clickable: false
  property bool pointer: clickable
  signal hovered()

  anchors.fill: parent
  hoverEnabled: true
  acceptedButtons: clickable ? Qt.LeftButton : Qt.NoButton
  cursorShape: pointer ? Qt.PointingHandCursor : Qt.ArrowCursor
  onContainsMouseChanged: if (containsMouse) hovered()
}
