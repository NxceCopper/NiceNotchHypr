import QtQuick

// Transport button — the accent play/pause circle, plain glyphs for the
// rest.  Used by NowPlaying (shared with the settings arranger preview).
Item {
    id: pb
    property string glyph: ""
    property bool primary: false
    signal clicked()

    implicitWidth: primary ? 38 : 26
    implicitHeight: primary ? 38 : 26

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: primary ? SettingsService.accentColor : "transparent"
    }

    Text {
        anchors.centerIn: parent
        text: pb.glyph
        color: primary ? "#0d0d0d" : "#ffffff"
        font { pixelSize: primary ? 17 : 15; family: "JetBrainsMono Nerd Font" }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: pb.clicked()
    }
}
