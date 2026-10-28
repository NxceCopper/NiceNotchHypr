import QtQuick

Item {
    id: btn
    width: size + 16
    height: size + 12

    property string icon: ""
    property int size: 18
    property bool highlight: false
    property bool enabled: true
    signal clicked()

    opacity: enabled ? 1.0 : 0.3

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: {
            if (!btn.enabled) return "transparent"
            if (btn.highlight && btnMouse.containsMouse) return SettingsService.accentColor
            if (btnMouse.containsMouse) return SettingsService.bgSurface
            return "transparent"
        }

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Text {
            anchors.centerIn: parent
            text: btn.icon
            font { pixelSize: btn.size; family: "SF Mono" }
            color: {
                if (btn.highlight && btnMouse.containsMouse) return SettingsService.bgBase
                return SettingsService.textPrimary
            }

            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (btn.enabled) btn.clicked()
        }
    }
}