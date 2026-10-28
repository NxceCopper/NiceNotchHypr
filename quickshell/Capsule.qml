import QtQuick

// Wi-Fi / Focus / Bluetooth / Game Mode tile: a pill with a round radio on
// the left and a label + subtitle beside it.  When the tile is taller than
// it is wide the pill stands up vertically — radio on top, text centered
// underneath.  Shared by the control centre and the settings arranger's
// live preview, so nothing is read from either root — every value arrives
// as a property.
Rectangle {
    id: cap
    property string iconOn: ""
    property string iconOff: ""
    property string label: ""
    property string sub: ""
    property bool checked: false
    signal toggled()
    signal expanded()

    readonly property bool vertical: height > width * 1.1
    // Too narrow for the label column (a 1 × 1 tile) — just the round
    // button on a small pill, centred.
    readonly property bool compact: !vertical && width < 110

    radius: vertical ? width / 2 : height / 2
    color: "#141211"

    // Hover tint (body only — the reference has no resting border)
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.rgba(1, 1, 1, 0.05)
        visible: bodyHover.containsMouse
    }

    // Body hit area: everything beside (wide) or below (tall) the button
    MouseArea {
        id: bodyHover
        anchors.fill: parent
        anchors.leftMargin: cap.vertical || cap.compact ? 0 : 52
        anchors.topMargin: cap.vertical ? 54 : 0
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cap.expanded()
    }

    // Label + subtitle — beside the radio when wide, under it when tall
    Column {
        visible: !cap.compact
        x: cap.vertical ? 8 : 62
        width: cap.vertical ? parent.width - 16 : parent.width - 62 - 12
        y: cap.vertical ? 58 : Math.round((parent.height - height) / 2)
        spacing: 1

        Text {
            width: parent.width
            text: cap.label
            color: SettingsService.textPrimary
            font { pixelSize: 13; family: "SF Pro Text"; bold: true }
            elide: Text.ElideRight
            horizontalAlignment: cap.vertical ? Text.AlignHCenter : Text.AlignLeft
        }

        Text {
            width: parent.width
            text: cap.sub
            color: SettingsService.textMuted
            font { pixelSize: 11; family: "SF Pro Text" }
            elide: Text.ElideRight
            horizontalAlignment: cap.vertical ? Text.AlignHCenter : Text.AlignLeft
        }
    }

    // Round radio button — sits above the body hit area
    Rectangle {
        id: circle
        x: cap.vertical || cap.compact ? Math.round((parent.width - width) / 2) : 14
        y: cap.vertical ? 12 : Math.round((parent.height - height) / 2)
        width: 36
        height: 36
        radius: 18
        color: cap.checked ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.07)

        Text {
            anchors.centerIn: parent
            text: cap.checked ? cap.iconOn : cap.iconOff
            color: cap.checked ? "#0d0d0d" : SettingsService.textMuted
            font { pixelSize: 17; family: "JetBrainsMono Nerd Font" }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: cap.toggled()
        }
    }
}
