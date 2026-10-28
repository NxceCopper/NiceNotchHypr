import QtQuick
import QtQuick.Layouts

// Notifications tile: header with Clear all over the live list of tracked
// notifications (per-row dismiss).  Shared by the control centre and the
// settings arranger preview, so the notification list is passed in rather
// than pulled from either root.
Rectangle {
    id: nc
    property var notifs: null

    readonly property int notifCount: notifs ? notifs.values.length : 0

    function clearAll() {
        if (!notifs) return;
        var list = notifs.values;
        for (var i = 0; i < list.length; i++) list[i].dismiss();
    }

    radius: 16
    color: "#141211"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            spacing: 6

            Text {
                text: "Notifications"
                color: SettingsService.textPrimary
                font { pixelSize: 12; family: "SF Pro Text" }
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: nc.notifCount > 0
                text: "Clear all"
                color: Qt.rgba(1, 1, 1, 0.55)
                font { pixelSize: 11; family: "SF Pro Text" }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: nc.clearAll()
                }
            }
        }

        ListView {
            id: notifList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: nc.notifs ? nc.notifs.values : []

            delegate: Rectangle {
                id: nCard
                required property var modelData

                width: notifList.width
                height: 72
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.055)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.10)

                        Text {
                            anchors.centerIn: parent
                            text: "󰂚"
                            color: SettingsService.textPrimary
                            font { pixelSize: 16; family: "JetBrainsMono Nerd Font" }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: (modelData.appName || "").replace(/\n/g, " ")
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font { pixelSize: 10; family: "SF Pro Text" }
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: (modelData.summary || "").replace(/\n/g, " ")
                            color: SettingsService.textPrimary
                            font { pixelSize: 12; family: "SF Pro Text"; bold: true }
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: (modelData.body || "").replace(/\n/g, " ")
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font { pixelSize: 10; family: "SF Pro Text" }
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "✕"
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: nCard.modelData.dismiss()
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: nCard.modelData.dismiss()
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                visible: nc.notifCount === 0
                text: "No Notifications"
                color: SettingsService.textMuted
                font { pixelSize: 10; family: "SF Pro Text" }
            }
        }
    }
}
