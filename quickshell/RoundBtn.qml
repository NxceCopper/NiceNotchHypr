import QtQuick

// Round toggle button that fills its 1 × 1 cell (Night Light).  Shared by
// the control centre and the settings arranger's live preview.
Rectangle {
    id: rb
    property string glyph: ""
    property bool checked: false
    property bool available: true
    signal clicked()

    radius: height / 2
    color: checked ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.07)
    opacity: available ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.rgba(1, 1, 1, 0.05)
        visible: rbHover.containsMouse && !rb.checked
    }

    Text {
        anchors.centerIn: parent
        text: rb.glyph
        color: rb.checked ? "#0d0d0d" : SettingsService.textPrimary
        font { pixelSize: 20; family: "JetBrainsMono Nerd Font" }
    }

    MouseArea {
        id: rbHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rb.clicked()
    }
}
