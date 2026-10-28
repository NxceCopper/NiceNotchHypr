import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Layouts
import QtQuick.Shapes
import "./dock"

ShellRoot {
    id: root

    // ── Global State ──
    property string activePanel: "none" // "none", "music", "calendar", "launcher", "wallpaper", "control", "workspaces"
    property bool isExpanded: activePanel !== "none"
    // Settings lives in its own FloatingWindow (see below) — completely
    // separate from the notch, so it can be moved and resized like any
    // other application window.
    property bool settingsOpen: false

    function togglePanel(name) {
        if (name === "settings") { settingsOpen = !settingsOpen; return }
        activePanel = (activePanel === name) ? "none" : name
    }

    // ── Keybindings ────────────────────────────────────────────────────────
    GlobalShortcut {
        name: "music"
        description: "Toggle the music panel in the notch"
        onPressed: root.togglePanel("music")
    }

    GlobalShortcut {
        name: "applet"
        description: "Toggle the app launcher in the notch"
        onPressed: root.togglePanel("launcher")
    }

    // SUPER + SHIFT + P — Wallpaper picker (opens inside the notch)
    GlobalShortcut {
        name: "wallpaper"
        description: "Open wallpaper picker"
        onPressed: root.togglePanel("wallpaper")
    }

    // SUPER + , — Settings (opens as its own toplevel window)
    GlobalShortcut {
        name: "settings"
        description: "Open settings window"
        onPressed: root.togglePanel("settings")
    }

    // SUPER + C — Control Center (opens inside the notch)
    GlobalShortcut {
        name: "control"
        description: "Open the control center"
        onPressed: root.togglePanel("control")
    }

    // SUPER + ` — Workspace overview (opens inside the notch)
    GlobalShortcut {
        name: "workspaces"
        description: "Toggle the workspace overview"
        onPressed: root.togglePanel("workspaces")
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.togglePanel("wallpaper") }
        function next(): void { WallpaperService.nextWallpaper() }
        function prev(): void { WallpaperService.prevWallpaper() }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.togglePanel("settings") }
    }

    IpcHandler {
        target: "music"
        function toggle(): void { root.togglePanel("music") }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.togglePanel("launcher") }
    }

    IpcHandler {
        target: "workspaces"
        function toggle(): void { root.togglePanel("workspaces") }
    }

    IpcHandler {
        target: "calendar"
        function toggle(): void { root.togglePanel("calendar") }
        // Open the panel straight onto one of the two views — the week
        // strip under the clock, or the full month grid
        function month(): void {
            if (root.activePanel !== "calendar") root.activePanel = "calendar";
            calendarPanel.view = "month";
        }
        function week(): void {
            if (root.activePanel !== "calendar") root.activePanel = "calendar";
            calendarPanel.view = "week";
        }
    }

    IpcHandler {
        target: "control"
        function toggle(): void { root.togglePanel("control") }
        // Open the panel straight onto a sub-page (sound / display) or a
        // tile drop-down (wifi / bt)
        function sub(name: string): void {
            if (root.activePanel !== "control") root.togglePanel("control");
            if (name === "wifi" || name === "bt") controlCenter.toggleMenu(name);
            else controlCenter.subPage = name;
        }
    }

    IpcHandler {
        target: "toggles"
        function focus(): void { TogglesService.toggleDnd() }
        function game(): void { TogglesService.toggleGameMode() }
        function night(): void { TogglesService.toggleNightLight() }
    }

    // ── Notification daemon (replaces swaync) ──
    NotificationServer {
        id: notifServer
        keepOnReload: true

        // Quickshell deletes untracked notifications immediately
        onNotification: notification => notification.tracked = true
    }

    // ── Notch space reservation ──
    // A transparent, input-less strip that reserves the top edge for the
    // notch so maximized/tiled apps tuck under it instead of being
    // overlapped by the pill. Separate from the notch window because that
    // one becomes a full-screen overlay while a menu is open (which must
    // not reserve anything).
    PanelWindow {
        anchors.top: true
        anchors.left: true
        anchors.right: true
        // Exactly up to the pill's bottom edge — no padding waste. (The
        // band must span the full width: hyprland reserves per-edge
        // bands, there is no partial-width exclusion.)
        implicitHeight: (SettingsService.isIsland ? 8 : 0)
            + SettingsService.notchHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Auto
        // Empty input region — pure space reservation, clicks pass
        // through to the notch window below/above it.
        mask: Region {}
    }

    // ── The Notch Window ──
    PanelWindow {
        id: notchWindow
        anchors.top: true
        anchors.left: true
        anchors.right: true
        // Full-screen overlay at all times. Resizing the surface down to a
        // pill strip made Hyprland run its own ~1s resize animation on
        // retract (the QML morph finished in 300ms, the surface crawled
        // after it). With a constant size there is nothing to animate —
        // the collapsed mask passes every click through except the pill,
        // and the shadow gets all the bleed room it needs.
        implicitHeight: screen ? screen.height : 1080
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        // Lets the applet's search field take the keyboard while a panel is open
        focusable: root.isExpanded
        // While expanded, grab the keyboard outright so the launcher's search
        // field receives typing without needing a click first (Wayland surfaces
        // otherwise only take focus on click).
        WlrLayershell.keyboardFocus: root.isExpanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // While collapsed, only the notch itself takes input — the rest of the
        // top strip passes clicks through to the desktop/windows behind.
        // Once expanded the whole overlay catches clicks so click-away closes it.
        mask: root.isExpanded ? null : notchRegion

        Region {
            id: notchRegion
            item: notchContent
        }

        // ── Notch Body ──
        Item {
            id: notchContent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            // Flush with the edge while idle (a real notch), then lifts clear
            // of the border as soon as you interact with it — Spotlight style.
            anchors.topMargin: topGap
            width: notchWidth
            height: notchHeight

            // ── Dynamic sizing ──
            property int topGap: {
                // Island lifts clear of the edge when a panel opens; the notch
                // stays flush with the top edge and simply expands downward.
                if (SettingsService.isIsland) return root.isExpanded ? 72 : 8
                return 0
            }
            property int notchWidth: root.isExpanded
                ? (root.activePanel === "launcher" ? 560
                   : root.activePanel === "control" ? 560
                   : root.activePanel === "music" ? 560
                   : root.activePanel === "wallpaper" ? 800
                   // The workspace overview morphs the island nearly
                   // fullscreen (upstream does the same): 5 cells wide.
                   : root.activePanel === "workspaces" ? 1780
                   : root.activePanel === "calendar"
                       ? (calendarPanel.view === "month" ? 420 : 260)
                   : 420)
                // Island is a fixed 130px pill; it widens into the workspace
                // capsule while the indicator flashes after a switch.
                : Math.max(workspaceIndicator.flashing ? workspaceIndicator.pillWidth : 0,
                           SettingsService.isIsland ? 130 : SettingsService.notchWidth)
            property int notchHeight: root.isExpanded
                ? expandedHeight
                : SettingsService.notchHeight
            property int notchRadius: root.isExpanded ? 26 : (SettingsService.isIsland ? 20 : 18)
            // The notch never leaves the edge, so it keeps its swept shoulders
            // in every state; the lifted island becomes a plain rounded pill.
            property int curveA: SettingsService.isIsland ? (root.isExpanded ? 26 : 20) : 10
            property int curveB: SettingsService.isIsland ? (root.isExpanded ? 26 : 20) : -10
            property int expandedHeight: {
                switch (root.activePanel) {
                    case "music": return SettingsService.expandedHeightMusic
                    case "calendar":
                        // Week strip is a short pill under the clock; the
                        // month grid gets the full calendar height.
                        return calendarPanel.view === "month"
                            ? SettingsService.expandedHeightCalendar : 96
                    case "launcher": return SettingsService.expandedHeightLauncher
                    case "wallpaper": return SettingsService.expandedHeightWallpaper
                    // 2 rows of workspace cells (0.18 scale) + padding
                    case "workspaces": return 425
                    case "control": {
                        // Fit the panel to the rows the layout actually uses —
                        // no empty grid rows under the last tile.
                        var ch = (SettingsService.expandedHeightControl - 90) / 8;
                        var rows = 1;
                        var l = SettingsService.controlLayout;
                        for (var i = 0; i < l.length; i++)
                            rows = Math.max(rows, l[i].y + l[i].h);
                        return Math.round(20 + rows * ch + (rows - 1) * 10);
                    }
                    default: return 36
                }
            }

            // Snappy morphs: OutCubic starts fast, so the snap back to the
            // pill feels immediate (InOutCubic spent its first beats
            // barely moving, which read as a sluggish retract).
            Behavior on topGap {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
            Behavior on curveA {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on curveB {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on notchWidth {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on notchHeight {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on notchRadius {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // ── Umbra shadow under the pill ──
            // A blurred dark rounded rect behind the notch body; the
            // window is transparent, so it composites over the desktop.
            // Tracks the notch geometry (collapse, expand, capsule flash).
            // Padded transparent host: layer blur renders inside the item's
            // (padded) bounds, so the host gives the bleed room on every
            // side. The shape sits behind the bg silhouette and reaches a
            // few px below the pill, so the underside umbra reads strongest.
            Item {
                id: notchShadow
                x: -44
                y: -40
                width: notchContent.width + 88
                height: notchContent.height + 88
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 40
                }
                Rectangle {
                    x: 47
                    y: 46
                    width: notchContent.width - 6
                    height: notchContent.height - 2
                    radius: notchContent.notchRadius
                    color: Qt.rgba(0, 0, 0, 0.7)
                }
            }

            // ── Background: flush notch whose top corners sweep outward into
            //    the screen edge; a floating rounded pill once a panel opens ──
            Shape {
                id: bg
                // Oversized so the outward flare at the top has room
                x: -16
                y: -1
                width: notchContent.width + 32
                height: notchContent.height + 2

                // Path coordinates are body-space, shifted into shape-space
                readonly property real ox: 16
                readonly property real oy: 1

                ShapePath {
                    strokeWidth: 1
                    // Pure black silhouette; a subtle outline only for the lifted island pill
                    strokeColor: SettingsService.isIsland && root.isExpanded ? SettingsService.borderColor : "transparent"
                    fillColor: "#000000"

                    // Left wall, down to the bottom-left corner
                    startX: bg.ox
                    startY: bg.oy + notchContent.curveA
                    PathLine {
                        x: bg.ox
                        y: bg.oy + notchContent.height - notchContent.notchRadius
                    }
                    PathCubic {
                        x: bg.ox + notchContent.notchRadius
                        y: bg.oy + notchContent.height
                        control1X: bg.ox
                        control1Y: bg.oy + notchContent.height - 0.4477 * notchContent.notchRadius
                        control2X: bg.ox + 0.4477 * notchContent.notchRadius
                        control2Y: bg.oy + notchContent.height
                    }
                    // Bottom edge, into the bottom-right corner
                    PathLine {
                        x: bg.ox + notchContent.width - notchContent.notchRadius
                        y: bg.oy + notchContent.height
                    }
                    PathCubic {
                        x: bg.ox + notchContent.width
                        y: bg.oy + notchContent.height - notchContent.notchRadius
                        control1X: bg.ox + notchContent.width - 0.4477 * notchContent.notchRadius
                        control1Y: bg.oy + notchContent.height
                        control2X: bg.ox + notchContent.width
                        control2Y: bg.oy + notchContent.height - 0.4477 * notchContent.notchRadius
                    }
                    // Right wall, up into the right shoulder
                    PathLine {
                        x: bg.ox + notchContent.width
                        y: bg.oy + notchContent.curveA
                    }
                    PathCubic {
                        x: bg.ox + notchContent.width - notchContent.curveB
                        y: bg.oy
                        control1X: bg.ox + notchContent.width
                        control1Y: bg.oy + 0.4477 * notchContent.curveA
                        control2X: bg.ox + notchContent.width - 0.4477 * notchContent.curveB
                        control2Y: bg.oy
                    }
                    // Top edge, into the left shoulder (back to the start)
                    PathLine {
                        x: bg.ox + notchContent.curveB
                        y: bg.oy
                    }
                    PathCubic {
                        x: bg.ox
                        y: bg.oy + notchContent.curveA
                        control1X: bg.ox + 0.4477 * notchContent.curveB
                        control1Y: bg.oy
                        control2X: bg.ox
                        control2Y: bg.oy + 0.4477 * notchContent.curveA
                    }
                }
            }

            // ── Hover + click area: covers the entire notch ──
            MouseArea {
                id: notchArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.isExpanded ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: root.togglePanel("calendar")
            }

            // ── Top Bar (idle state only — panels hide the clock) ──
            Item {
                id: topBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.isExpanded ? 0 : notchContent.height
                visible: !root.isExpanded
                // The clock steps aside while the workspace capsule flashes.
                opacity: (root.isExpanded || workspaceIndicator.flashing) ? 0 : 1

                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
                }

                // ── Center: Clock ──
                NotchClock {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── Workspace capsule (ported from dynamic-island-hyprland) ──
            // Rendered inside the notch: the notch widens into the capsule
            // on a workspace switch, clock fades out, then it folds back.
            WorkspaceIndicator {
                id: workspaceIndicator
                anchors.fill: parent
                blocked: root.isExpanded
                onOverviewRequested: root.togglePanel("workspaces")
            }

            // ── Expanded Content Area ──
            Item {
                id: expandedArea
                anchors.top: topBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                clip: true
                transformOrigin: Item.Top
                scale: root.isExpanded ? 1 : 0.94

                Behavior on scale {
                    NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
                }

                // ── Music Panel ──
                MusicPanel {
                    anchors.fill: parent
                    visible: root.activePanel === "music"
                    opacity: root.activePanel === "music" ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
                    }
                }

                // ── App Launcher Panel (ported from dynamic-island-hyprland) ──
                LauncherPanel {
                    anchors.fill: parent
                    visible: root.activePanel === "launcher"
                    showCondition: root.activePanel === "launcher"

                    onLaunched: root.activePanel = "none"
                    onDismissed: root.activePanel = "none"
                }

                // ── Workspace Overview (ported from dynamic-island-hyprland) ──
                WorkspaceOverviewScene {
                    anchors.fill: parent
                    screen: notchWindow.screen
                    showCondition: root.activePanel === "workspaces"
                    previewsEnabled: root.activePanel === "workspaces"
                    wallpaperPath: WallpaperService.currentWallpaper
                    onCloseRequested: root.activePanel = "none"
                }

                // ── Wallpaper Panel (inside the notch) ──
                WallpaperManager {
                    anchors.fill: parent
                    visible: root.activePanel === "wallpaper"
                    opacity: root.activePanel === "wallpaper" ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
                    }

                    onDismissed: root.activePanel = "none"
                }

            }

            // ── Calendar Panel — fills the pill so the week view can draw
            //    its own copy of the island clock (panels hide the topBar).
            //    Clicking the week strip folds it out to the month grid;
            //    shell.qml morphs the pill between the two sizes.
            CalendarPanel {
                id: calendarPanel
                anchors.fill: notchContent
                visible: root.activePanel === "calendar"
                opacity: root.activePanel === "calendar" ? 1 : 0
                transformOrigin: Item.Top
                scale: root.isExpanded ? 1 : 0.94
                Behavior on scale {
                    NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
                }
            }

            // ── Control Center — fills the pill exactly.  Its grid maths
            //    assume the full notch height (10px padding top and bottom);
            //    living inside expandedArea's 8px inset doubled the top
            //    padding and clipped the last row's bottom.
            ControlCenter {
                id: controlCenter
                anchors.fill: notchContent
                notifs: notifServer.trackedNotifications
                visible: root.activePanel === "control"
                opacity: root.activePanel === "control" ? 1 : 0
                // Same entrance as the other panels: grow down from the top
                transformOrigin: Item.Top
                scale: root.isExpanded ? 1 : 0.94
                Behavior on scale {
                    NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
                }

                onDismissed: root.activePanel = "none"
            }
        }

        // ── Click-away to close ──
        MouseArea {
            anchors.fill: parent
            z: -10
            visible: root.isExpanded
            onClicked: root.activePanel = "none"
        }
    }

    // ── Optional shell-drawn wallpaper background (bottom layer) ──
    // Off by default: awww draws the desktop and gets the animated
    // transitions. Toggle in Settings → Appearance → Shell-drawn background.
    BackgroundWindow {
        id: backgroundWindow
    }

    // ── Application dock (ported from hyprland-dock, MIT) ─────────────────
    // macOS-style dock at the bottom with pointer magnification. Auto-dodge
    // slides it out when a window on the active workspace overlaps its
    // area; hovering the screen edge summons it back.
    HyprlandData {
        id: dockHyprlandData
    }

    DockHost {
        hyprlandData: dockHyprlandData
        configPath: Quickshell.env("HOME") + "/.config/hyprland-dock/dock.json"
    }

    // ── Settings — a standard toplevel window, not part of the notch ──
    // Hyprland manages it like any other app window: drag its titlebar (or
    // SUPER+drag) to move, drag its edges/borders to resize.
    FloatingWindow {
        id: settingsWindow
        title: "Quickshell Settings"
        visible: root.settingsOpen
        color: "transparent"
        implicitWidth: 880
        implicitHeight: SettingsService.expandedHeightSettings
        minimumSize: Qt.size(480, 320)

        // Remember the user's own resize across close/reopen; once they
        // resize by hand, their size wins over the settings slider.
        onVisibleChanged: {
            if (!visible) {
                if (implicitWidth !== width) implicitWidth = width
                if (implicitHeight !== height) implicitHeight = height
            }
        }

        // Sync state when closed by the compositor (e.g. Hyprland kill bind)
        onClosed: root.settingsOpen = false

        SettingsPanel {
            anchors.fill: parent
            visible: settingsWindow.visible
            notifs: notifServer.trackedNotifications

            onDismissed: root.settingsOpen = false
        }
    }

}