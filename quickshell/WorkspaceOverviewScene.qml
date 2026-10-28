// Ported from dynamic-island-hyprland (St0rmosu), MIT License — see
// LICENSE-dynamic-island-hyprland.txt. Adapted: grabs keyboard focus on
// show (Escape close) since we host it inside the notch overlay.
import QtQuick

Item {
    id: root

    property var screen: null
    property bool showCondition: false
    property bool previewsEnabled: false
    property string textFontFamily: "SF Pro Text"
    property string heroFontFamily: "SF Pro Text"
    property string wallpaperPath: ""
    property real windowCornerRadius: 22

    property alias overviewView: overviewView
    property alias overviewDataReady: hyprlandData.ready

    signal closeRequested()

    anchors.fill: parent

    onShowConditionChanged: {
        if (showCondition)
            Qt.callLater(function() { overviewView.grabKeyboardFocus() })
    }

    HyprlandData {
        id: hyprlandData
    }

    WorkspaceOverviewLayer {
        id: overviewView

        anchors.centerIn: parent
        screen: root.screen
        hyprlandData: hyprlandData
        showCondition: root.showCondition
        previewsEnabled: root.previewsEnabled
        textFontFamily: root.textFontFamily
        heroFontFamily: root.heroFontFamily
        wallpaperPath: root.wallpaperPath
        windowCornerRadius: root.windowCornerRadius
        onCloseRequested: root.closeRequested()
    }
}
