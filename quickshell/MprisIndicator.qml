import QtQuick
import Quickshell.Services.Mpris

Item {
    id: indicator
    width: indicatorDot.width
    height: indicatorDot.height
    visible: hasPlayer

    property bool hasPlayer: {
        var players = Mpris.players.values
        if (!players) return false
        for (var i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) return true
        }
        return false
    }

    Rectangle {
        id: indicatorDot
        width: 8
        height: 8
        radius: 4
        color: SettingsService.accentGreen

        SequentialAnimation on opacity {
            running: indicator.hasPlayer
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
        }
    }
}