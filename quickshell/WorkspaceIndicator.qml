// Workspace capsule merged into the notch — adapted from
// dynamic-island-hyprland's WorkspaceFloatingIsland (St0rmosu), MIT License —
// see LICENSE-dynamic-island-hyprland.txt. Instead of a separate window, the
// notch itself widens into the capsule while flashing (shell.qml reads
// `flashing` + `pillWidth` to morph its width and hide the clock).
// Click a slot to jump, scroll to cycle, right-click for the overview.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io

Item {
    id: root

    // Set by the shell while a notch panel is open (capsule yields to it).
    property bool blocked: false
    signal overviewRequested()

    // Shell reads this to morph the notch wider while the capsule shows.
    readonly property bool flashing: showCapsule

    readonly property int totalWorkspaces: 5
    readonly property string textFontFamily: "SF Pro Text"

    readonly property int currentWorkspace: {
        const ws = Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace
            ? Hyprland.focusedMonitor.activeWorkspace : null;
        if (ws && ws.id >= 1 && ws.id <= totalWorkspaces)
            return ws.id;
        return -1;
    }

    property var wsAppMap: ({})
    property var occupiedSet: ({})
    property bool showCapsule: false

    readonly property real itemSize: Math.min(26, Math.max(18, height - 12))
    readonly property real itemSpacing: 5
    readonly property real paddingH: 8
    readonly property real pillWidth: paddingH * 2 + totalWorkspaces * itemSize
        + (totalWorkspaces - 1) * itemSpacing

    anchors.fill: parent
    visible: showCapsule && !blocked
    opacity: showCapsule ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    // ── capsule row (the notch bg itself is the capsule background) ──

    Item {
        id: row
        width: root.pillWidth
        height: root.height
        anchors.horizontalCenter: parent.horizontalCenter

        // Right-click / wheel anywhere on the row (behind the slots).
        MouseArea {
            id: rowArea
            anchors.fill: parent
            z: 0
            hoverEnabled: true
            acceptedButtons: Qt.RightButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton)
                    root.overviewRequested();
            }
            onWheel: function(wheel) {
                const dir = wheel.angleDelta.y > 0 ? "e-1" : "e+1";
                try {
                    Hyprland.dispatch("hl.dsp.focus({ workspace = '" + dir + "' })");
                } catch (e) {
                    Quickshell.execDetached(["hyprctl", "dispatch",
                        "hl.dsp.focus({ workspace = '" + dir + "' })"]);
                }
            }
        }

        // ── occupied slices (merged capsule) ─────────────────────

        Repeater {
            model: root.totalWorkspaces
            delegate: Rectangle {
                id: occupiedBgSlice
                required property int index
                readonly property int wsId: index + 1
                readonly property bool isOcc: (root.occupiedSet[wsId] === true || wsId === root.currentWorkspace)
                readonly property bool prevOcc: (index > 0 && (root.occupiedSet[wsId - 1] === true || (wsId - 1) === root.currentWorkspace))
                readonly property bool nextOcc: (index < root.totalWorkspaces - 1 && (root.occupiedSet[wsId + 1] === true || (wsId + 1) === root.currentWorkspace))

                x: root.paddingH + index * (root.itemSize + root.itemSpacing)
                y: (root.height - root.itemSize) / 2
                width: root.itemSize + (nextOcc ? root.itemSpacing : 0)
                height: root.itemSize
                visible: isOcc

                color: Qt.rgba(255, 255, 255, 0.08)
                topLeftRadius: prevOcc ? 0 : root.itemSize / 2
                bottomLeftRadius: prevOcc ? 0 : root.itemSize / 2
                topRightRadius: nextOcc ? 0 : root.itemSize / 2
                bottomRightRadius: nextOcc ? 0 : root.itemSize / 2
                z: 1
            }
        }

        // ── active workspace bubble ──────────────────────────────

        Rectangle {
            id: activeBubble
            width: root.itemSize
            height: root.itemSize
            radius: root.itemSize / 2
            color: "#ffffff"
            z: 2

            visible: root.currentWorkspace >= 1 && root.currentWorkspace <= root.totalWorkspaces
            x: visible ? root.paddingH + (root.currentWorkspace - 1) * (root.itemSize + root.itemSpacing) : 0
            y: (root.height - root.itemSize) / 2

            Behavior on x {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
        }

        // ── slots: app icon / number / dot ───────────────────────

        Repeater {
            model: root.totalWorkspaces
            delegate: Item {
                id: wsSlot
                required property int index
                readonly property int wsId: index + 1
                readonly property bool isActive: (wsId === root.currentWorkspace)
                readonly property bool isOccupied: (root.occupiedSet[wsId] === true || isActive)
                readonly property var appInfo: root.wsAppMap[wsId]
                readonly property string appIconSource: appInfo ? (appInfo.icon || "") : ""
                readonly property bool hasAppIcon: appIconSource !== ""

                x: root.paddingH + index * (root.itemSize + root.itemSpacing)
                y: (root.height - root.itemSize) / 2
                width: root.itemSize
                height: root.itemSize
                z: 3

                ClippingRectangle {
                    id: slotAppIconFrame
                    anchors.centerIn: parent
                    width: Math.round(root.itemSize * 0.78)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: wsSlot.hasAppIcon && !slotAppIcon.loadError

                    Image {
                        id: slotAppIcon
                        anchors.centerIn: parent
                        width: Math.round(slotAppIconFrame.width * 1.25)
                        height: width
                        source: wsSlot.appIconSource
                        sourceSize: Qt.size(width * 2, width * 2)
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        smooth: true
                        property bool loadError: false

                        onStatusChanged: {
                            if (status === Image.Error)
                                loadError = true;
                            else if (status === Image.Ready)
                                loadError = false;
                        }
                    }
                }

                Text {
                    id: slotText
                    anchors.centerIn: parent
                    text: String(wsSlot.wsId)
                    font.family: root.textFontFamily
                    font.pixelSize: Math.round(root.itemSize * 0.44)
                    font.weight: wsSlot.isActive ? Font.Bold : Font.DemiBold
                    color: wsSlot.isActive ? "#0b0d13" : "#f0f3fa"
                    visible: (!wsSlot.hasAppIcon || slotAppIcon.loadError) && (wsSlot.isActive || wsSlot.isOccupied)
                }

                Rectangle {
                    id: emptyDot
                    anchors.centerIn: parent
                    width: Math.round(root.itemSize * 0.20)
                    height: width
                    radius: width / 2
                    color: "#525766"
                    visible: !wsSlot.isActive && !wsSlot.isOccupied
                }

                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    // Hyprland 0.56+ dispatches via a Lua DSL (hl.dsp.*).
                    function focusWs(id) {
                        try {
                            Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })");
                        } catch (e) {
                            Quickshell.execDetached(["hyprctl", "dispatch",
                                "hl.dsp.focus({ workspace = " + id + " })"]);
                        }
                    }
                    function cycleWs(dir) {
                        try {
                            Hyprland.dispatch("hl.dsp.focus({ workspace = '" + dir + "' })");
                        } catch (e) {
                            Quickshell.execDetached(["hyprctl", "dispatch",
                                "hl.dsp.focus({ workspace = '" + dir + "' })"]);
                        }
                    }

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.LeftButton) {
                            focusWs(wsSlot.wsId);
                        } else if (mouse.button === Qt.RightButton) {
                            root.overviewRequested();
                        }
                    }

                    onWheel: function(wheel) {
                        if (wheel.angleDelta.y > 0)
                            cycleWs("e-1");
                        else if (wheel.angleDelta.y < 0)
                            cycleWs("e+1");
                    }
                }
            }
        }
    }

    // ── app icon resolution + client tracking ───────────────────

    function resolveAppIcon(appClass) {
        if (!appClass || appClass === "") return "";
        const lower = appClass.toLowerCase();

        const overrides = {
            "zen": "zen-browser",
            "zen-alpha": "zen-browser",
            "foot": "foot",
            "footclient": "foot",
            "discord": "discord",
            "webcord": "discord",
            "vesktop": "discord",
            "spotify": "spotify",
            "code": "visual-studio-code",
            "code-url-handler": "visual-studio-code",
            "vscodium": "vscodium",
            "firefox": "firefox",
            "firefox-developer-edition": "firefox-developer-edition",
            "google-chrome": "google-chrome",
            "chromium": "chromium",
            "steam": "steam",
            "thunar": "system-file-manager",
            "nautilus": "org.gnome.Nautilus",
            "dolphin": "system-file-manager",
            "kitty": "kitty",
            "alacritty": "Alacritty",
            "wezterm": "org.wezfurlong.wezterm",
            "pavucontrol": "pavucontrol",
            "obs": "com.obsproject.Studio",
            "telegramdesktop": "telegram",
            "org.telegram.desktop": "telegram",
            "com.gabm.satty": "satty",
            "satty": "satty"
        };

        if (overrides[lower]) {
            const p = Quickshell.iconPath(overrides[lower]);
            if (p && p !== "") return p;
        }

        let p = Quickshell.iconPath(lower);
        if (p && p !== "") return p;

        p = Quickshell.iconPath(appClass);
        if (p && p !== "") return p;

        const parts = appClass.split(".");
        if (parts.length > 1) {
            const lastPart = parts[parts.length - 1].toLowerCase();
            p = Quickshell.iconPath(lastPart);
            if (p && p !== "") return p;
        }

        return "";
    }

    Process {
        id: fetchClientsProcess
        command: ["hyprctl", "clients", "-j"]
        running: false

        stdout: StdioCollector {
            onDataChanged: {
                if (!data) return;
                try {
                    const parsed = JSON.parse(data);
                    const appMap = {};
                    const occMap = {};

                    for (let i = 0; i < parsed.length; i++) {
                        const win = parsed[i];
                        if (!win.mapped || !win.workspace) continue;
                        const wsId = win.workspace.id;
                        if (wsId < 1 || wsId > root.totalWorkspaces) continue;

                        occMap[wsId] = true;

                        const appClass = String(win.class || win.initialClass || "").trim();
                        if (appClass === "") continue;

                        const area = (win.size && win.size.length >= 2) ? (win.size[0] * win.size[1]) : 0;
                        const existing = appMap[wsId];
                        if (!existing || area > existing.area) {
                            appMap[wsId] = {
                                clazz: appClass,
                                area: area,
                                icon: root.resolveAppIcon(appClass)
                            };
                        }
                    }

                    if (Hyprland.workspaces && Hyprland.workspaces.values) {
                        const hws = Hyprland.workspaces.values;
                        for (let j = 0; j < hws.length; j++) {
                            const hid = hws[j].id;
                            if (hid >= 1 && hid <= root.totalWorkspaces) {
                                occMap[hid] = true;
                            }
                        }
                    }

                    root.wsAppMap = appMap;
                    root.occupiedSet = occMap;
                } catch (e) {
                    console.log("[WorkspaceIndicator] Parse error:", e);
                }
            }
        }
    }

    Timer {
        id: refreshDebounce
        interval: 80
        repeat: false
        onTriggered: {
            if (!fetchClientsProcess.running)
                fetchClientsProcess.running = true;
        }
    }

    function triggerRefresh() {
        refreshDebounce.restart();
    }

    Timer {
        id: hideTimer
        interval: 1400
        repeat: false
        onTriggered: root.showCapsule = false
    }

    function flash() {
        triggerRefresh();
        showCapsule = true;
        hideTimer.restart();
    }

    Component.onCompleted: triggerRefresh()

    onBlockedChanged: {
        // Reveal again once the blocking panel closes (timer still running).
        if (!blocked && showCapsule)
            hideTimer.restart();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!event) return;
            const ev = event.name;
            if (ev === "workspace" || ev === "workspacev2" || ev === "focusedmon" || ev === "focusedmonv2") {
                root.flash();
            } else if (ev === "openwindow" || ev === "closewindow" || ev === "movewindow" ||
                       ev === "createworkspace" || ev === "destroyworkspace") {
                root.triggerRefresh();
            }
        }
        function onFocusedWorkspaceChanged() {
            root.flash();
        }
    }
}
