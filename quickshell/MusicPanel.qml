import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris

// Wide media card in the expanded notch, matched to the brief: blurred album
// art behind everything, big cover on the left, details and transport on the
// right. Lives at 560 × expandedHeightMusic inside the clipped notch area.
Rectangle {
    id: musicPanel
    radius: 18              // notch corner radius minus the expanded-area inset
    clip: true
    color: SettingsService.bgBase

    // ── Find the active player ──
    property var player: {
        var players = Mpris.players.values
        if (!players || players.length === 0) return null
        // Prefer the currently playing player
        for (var i = 0; i < players.length; i++)
            if (players[i].playbackState === MprisPlaybackState.Playing) return players[i]
        return players[0]
    }

    property bool hasPlayer: player !== null
    property bool isPlaying: hasPlayer && player.playbackState === MprisPlaybackState.Playing
    property string title: hasPlayer ? (player.trackTitle || "") : ""
    property string artist: hasPlayer ? (player.trackArtist || "") : ""
    property string album: hasPlayer ? (player.trackAlbum || "") : ""
    property string app: hasPlayer ? (player.identity || "") : ""
    property string artUrl: hasPlayer ? (player.trackArtUrl || "") : ""
    readonly property bool hasArt: artUrl !== "" && bgArt.status === Image.Ready

    readonly property real ratio: {
        if (!hasPlayer || !player.length || player.length <= 0) return 0
        return Math.max(0, Math.min(1, player.position / player.length))
    }

    function fmtTime(s) {
        if (!s || s < 0 || isNaN(s)) return "0:00"
        var m = Math.floor(s / 60), sec = Math.floor(s % 60)
        return m + ":" + (sec < 10 ? "0" : "") + sec
    }

    // ── Blurred art backdrop, masked to the panel's rounded corners ──
    Image {
        id: bgArt
        anchors.fill: parent
        source: musicPanel.artUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false              // sampled by the blur, never drawn directly
        sourceSize: Qt.size(128, 128)   // tiny source upscaled = smooth and cheap
    }

    Item {
        id: bgBox
        anchors.fill: parent
        visible: musicPanel.hasArt
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: bgMask
        }

        FastBlur {
            anchors.fill: parent
            source: bgArt
            radius: 40
        }

        // Dark wash so the text stays readable over any artwork
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
        }
    }

    Rectangle {
        id: bgMask
        anchors.fill: parent
        radius: musicPanel.radius
        color: "white"
        visible: false
        layer.enabled: true
    }

    // ── No player fallback ──
    Column {
        anchors.centerIn: parent
        spacing: 6
        visible: !musicPanel.hasPlayer

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰎈"
            color: SettingsService.textMuted
            font { pixelSize: 26; family: "JetBrainsMono Nerd Font" }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No media player active"
            color: Qt.rgba(1, 1, 1, 0.5)
            font { pixelSize: 12; family: "SF Pro Text" }
        }
    }

    // ── Player UI ──
    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 18
        visible: musicPanel.hasPlayer

        // Album cover — square, as tall as the card
        Rectangle {
            id: cover
            Layout.fillHeight: true
            Layout.preferredWidth: height
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.06)

            // Cover art, masked to the rounded corners (clip alone only cuts
            // to the bounding box, leaving square art corners)
            Item {
                id: coverBox
                anchors.fill: parent
                visible: coverImg.status === Image.Ready
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: coverMask
                }

                Image {
                    id: coverImg
                    anchors.fill: parent
                    source: musicPanel.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Rectangle {
                id: coverMask
                anchors.fill: parent
                radius: 16
                color: "white"
                visible: false
                layer.enabled: true
            }

            // Fallback glyph when there is no art
            Text {
                anchors.centerIn: parent
                visible: coverImg.status !== Image.Ready
                text: "󰎈"
                font { pixelSize: 34; family: "JetBrainsMono Nerd Font" }
                color: SettingsService.textMuted
            }

            // Hairline so dark covers separate from the dark card
            Rectangle {
                anchors.fill: parent
                radius: 16
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
            }
        }

        // ── Details + transport ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: musicPanel.title
                color: "#ffffff"
                font { pixelSize: 19; family: "SF Pro Text"; bold: true }
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: musicPanel.artist
                color: Qt.rgba(1, 1, 1, 0.8)
                font { pixelSize: 12; family: "SF Pro Text" }
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: {
                    var parts = [];
                    if (musicPanel.album !== "") parts.push(musicPanel.album);
                    if (musicPanel.app !== "") parts.push(musicPanel.app);
                    return parts.join(" · ");
                }
                color: Qt.rgba(1, 1, 1, 0.45)
                font { pixelSize: 10; family: "SF Pro Text" }
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 4 }

            // Progress — tap to seek when the player allows it
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 16
                spacing: 8

                Text {
                    Layout.preferredWidth: 30
                    horizontalAlignment: Text.AlignRight
                    text: musicPanel.fmtTime(musicPanel.hasPlayer ? musicPanel.player.position : 0)
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font { pixelSize: 10; family: "SF Pro Text" }
                }

                Item {
                    id: seekTrack
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.18)
                    }

                    Rectangle {
                        width: parent.width * musicPanel.ratio
                        height: parent.height
                        radius: 2
                        color: SettingsService.accentColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (musicPanel.hasPlayer && musicPanel.player.canSeek && musicPanel.player.length > 0)
                                musicPanel.player.setPosition(
                                    musicPanel.player.length * Math.max(0, Math.min(1, mouse.x / parent.width)));
                        }
                    }
                }

                Text {
                    Layout.preferredWidth: 30
                    text: musicPanel.fmtTime(musicPanel.hasPlayer ? musicPanel.player.length : 0)
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font { pixelSize: 10; family: "SF Pro Text" }
                }
            }

            // Transport
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                Layout.topMargin: 4
                spacing: 24

                Item { Layout.fillWidth: true }

                // Previous
                Rectangle {
                    id: prevBtn
                    property bool hovered: prevHover.containsMouse
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: prevHover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    opacity: musicPanel.hasPlayer && musicPanel.player.canGoPrevious ? 1 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        color: Qt.rgba(1, 1, 1, 0.9)
                        font { pixelSize: 17; family: "JetBrainsMono Nerd Font" }
                    }

                    MouseArea {
                        id: prevHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (musicPanel.player.canGoPrevious) musicPanel.player.previous()
                    }
                }

                // Play / pause — the light circle from the brief
                Rectangle {
                    id: playBtn
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    radius: 23
                    color: playHover.containsMouse
                        ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.92)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: musicPanel.isPlaying ? "󰏤" : "󰐊"
                        color: "#111111"
                        font { pixelSize: 20; family: "JetBrainsMono Nerd Font" }
                    }

                    MouseArea {
                        id: playHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!musicPanel.hasPlayer) return;
                            if (musicPanel.isPlaying) musicPanel.player.pause();
                            else musicPanel.player.play();
                        }
                    }
                }

                // Next
                Rectangle {
                    id: nextBtn
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: nextHover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    opacity: musicPanel.hasPlayer && musicPanel.player.canGoNext ? 1 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        color: Qt.rgba(1, 1, 1, 0.9)
                        font { pixelSize: 17; family: "JetBrainsMono Nerd Font" }
                    }

                    MouseArea {
                        id: nextHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (musicPanel.player.canGoNext) musicPanel.player.next()
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
