import QtQuick
import QtQuick.Layouts

// Labeled slider card (Display / Sound): title + chevron header over a
// fat pill slider whose icon rides inside the accent fill.  When the tile
// is taller than it is wide the slider stands up vertically — the well
// becomes a tall pill and the fill rises from the bottom with the icon
// riding its top edge.  Shared by the control centre and the settings
// arranger's live preview — values and actions arrive as properties,
// nothing is pulled from a root.
Rectangle {
    id: sc
    property string title: ""
    property string icon: ""
    property real value: 0
    property bool dragging: false
    signal moved(real v)
    signal iconClicked()
    signal expanded()          // chevron → full sub-page

    readonly property real clamped: Math.max(0, Math.min(1, value))
    readonly property bool vertical: height > width * 1.1

    radius: 16
    color: "#141211"

    function updateFrom(e) {
        moved(sc.vertical
            ? (track.height > 0
                ? Math.max(0, Math.min(1, (track.height - e.y) / track.height))
                : 0)
            : (track.width > 0
                ? Math.max(0, Math.min(1, e.x / track.width))
                : 0));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 6
        anchors.bottomMargin: 9
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 14
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: sc.title
                color: SettingsService.textPrimary
                font { pixelSize: 12; family: "SF Pro Text" }
                elide: Text.ElideRight
            }

            Text {
                text: "›"
                color: Qt.rgba(1, 1, 1, 0.4)
                font { pixelSize: 15; family: "SF Pro Text" }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sc.expanded()
                }
            }
        }

        Item {
            id: track
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: sc.vertical ? 40 : 18

            // ── Wide: fat pill, fill from the left ──
            Rectangle {
                visible: !sc.vertical
                anchors.fill: parent
                radius: height / 2
                color: "#0b0907"
            }

            Rectangle {
                id: fill
                visible: !sc.vertical
                width: parent.width * sc.clamped
                height: parent.height
                radius: height / 2
                color: SettingsService.accentColor
            }

            // ── Tall: upright pill, fill from the bottom ──
            Rectangle {
                visible: sc.vertical
                anchors.fill: parent
                radius: width / 2
                color: "#0b0907"
            }

            Rectangle {
                id: fillV
                visible: sc.vertical
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * sc.clamped
                radius: width / 2
                color: SettingsService.accentColor
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: e => { sc.dragging = true; sc.updateFrom(e); }
                onPositionChanged: e => { if (sc.dragging) sc.updateFrom(e); }
                onReleased: sc.dragging = false
                onCanceled: sc.dragging = false
            }

            // Icon sits inside the fill — left edge when wide, top when tall
            Item {
                x: sc.vertical ? (parent.width - width) / 2 : 8
                y: sc.vertical
                    ? Math.max(4, Math.min(parent.height - 28,
                        parent.height * (1 - sc.clamped) + 2))
                    : (parent.height - height) / 2
                width: 24
                height: 24

                Text {
                    anchors.centerIn: parent
                    text: sc.icon
                    color: sc.vertical
                        ? (fillV.height > 34 ? "#0d0d0d" : Qt.rgba(1, 1, 1, 0.75))
                        : (fill.width > 34 ? "#0d0d0d" : Qt.rgba(1, 1, 1, 0.75))
                    font { pixelSize: 15; family: "JetBrainsMono Nerd Font" }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sc.iconClicked()
                }
            }
        }
    }
}
