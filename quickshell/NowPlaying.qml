import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris

// Blurred-art now playing card: title/artist up top, transport centred,
// progress bar hugging the bottom edge.  Reads MPRIS directly so both the
// control centre and the settings arranger preview show the same live
// track without any wiring.
Rectangle {
    id: np
    radius: 16
    color: np.trackArt !== "" ? "#000000" : "#141211"
    clip: true

    readonly property var player: {
        var ps = Mpris.players.values;
        return (ps && ps.length > 0) ? ps[0] : null;
    }
    readonly property string trackTitle: player && player.trackTitle ? player.trackTitle : ""
    readonly property string trackArtist: player && player.trackArtist ? player.trackArtist : ""
    readonly property string trackArt: player && player.trackArtUrl ? player.trackArtUrl : ""
    readonly property bool playing: player ? player.isPlaying : false
    property real mediaPos: 0
    readonly property real mediaRatio: {
        if (!player || player.length <= 0) return 0;
        return Math.max(0, Math.min(1, mediaPos / player.length));
    }

    function syncPos() {
        if (player && player.positionSupported) mediaPos = player.position;
    }
    onPlayerChanged: syncPos()
    Component.onCompleted: syncPos()

    // Keep the playhead moving while visible
    Timer {
        interval: 1000
        repeat: true
        running: np.visible
        onTriggered: np.syncPos()
    }

    // Art + dark wash, masked to the card's rounded corners — `clip` on the
    // card only cuts to the bounding box, which left square art corners.
    // NB: a parent must never key its `visible` off a child's `visible`,
    // that is the *effective* value and creates a binding loop; both read
    // trackArt directly instead.
    Item {
        id: artBox
        anchors.fill: parent
        visible: np.trackArt !== ""
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: npMask
        }

        Image {
            id: npArt
            anchors.fill: parent
            source: np.trackArt
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: np.trackArt !== "" ? 0.42 : 0
        }
    }

    Rectangle {
        id: npMask
        anchors.fill: parent
        radius: np.radius
        color: "white"
        visible: false
        layer.enabled: true
    }

    // Idle state
    Column {
        anchors.centerIn: parent
        spacing: 4
        visible: np.trackTitle === ""

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰎈"
            color: Qt.rgba(1, 1, 1, 0.4)
            font { pixelSize: 24; family: "JetBrainsMono Nerd Font" }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Not Playing"
            color: Qt.rgba(1, 1, 1, 0.45)
            font { pixelSize: 10; family: "SF Pro Text" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 10
        anchors.bottomMargin: 30
        spacing: 0
        visible: np.trackTitle !== ""

        Text {
            Layout.fillWidth: true
            text: np.trackTitle
            color: "#ffffff"
            font { pixelSize: 15; family: "SF Pro Text"; bold: true }
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: np.trackArtist !== "" ? np.trackArtist : "Unknown artist"
            color: Qt.rgba(1, 1, 1, 0.62)
            font { pixelSize: 12; family: "SF Pro Text" }
            elide: Text.ElideRight
        }

        Item {
            Layout.fillHeight: true
            Layout.minimumHeight: 4
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 24

            PlayBtn {
                glyph: "󰒮"
                onClicked: if (np.player) np.player.previous()
            }

            PlayBtn {
                primary: true
                glyph: np.playing ? "󰏤" : "󰐊"
                onClicked: if (np.player) np.player.togglePlaying()
            }

            PlayBtn {
                glyph: "󰒭"
                onClicked: if (np.player) np.player.next()
            }
        }

        Item {
            Layout.fillHeight: true
            Layout.minimumHeight: 4
        }
    }

    // Progress bar, edge to edge along the bottom of the card
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: 11
        height: 5
        radius: 2.5
        color: Qt.rgba(1, 1, 1, 0.16)
        visible: np.player && np.player.lengthSupported

        Rectangle {
            width: parent.width * np.mediaRatio
            height: parent.height
            radius: 2.5
            color: SettingsService.accentColor
        }

        Rectangle {
            x: Math.max(0, parent.width * np.mediaRatio - 3.5)
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: SettingsService.accentColor
            visible: np.mediaRatio > 0
        }
    }
}
