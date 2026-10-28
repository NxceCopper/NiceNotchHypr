import QtQuick

Rectangle {
  id: root

  required property string text
  signal triggered()

  implicitWidth: 168
  implicitHeight: 38
  radius: 8
  color: hover.hovered && enabled ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
  opacity: enabled ? 1 : 0.42

  Text {
    anchors {
      verticalCenter: parent.verticalCenter
      left: parent.left
      leftMargin: 12
    }
    text: root.text
    color: "#f5f5f5"
    font.pixelSize: 13
  }

  HoverHandler {
    id: hover
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    enabled: root.enabled
    acceptedButtons: Qt.LeftButton
    onTapped: root.triggered()
  }
}
