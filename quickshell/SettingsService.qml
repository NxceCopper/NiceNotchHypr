pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Default values
    property color accentColor: "#9fe8a0"
    property color bgBase: "#000000"
    property color bgSurface: "#24283b"
    property color bgOverlay: "#cc000000" // dimmed backdrop behind overlay panels
    property color textPrimary: "#e0e0e0"
    property color textMuted: "#666666"
    property color borderColor: "#333333"
    property color accentGreen: "#4ade80"

    // Notch/island settings
    property int notchWidth: 200
    property int notchHeight: 36
    property bool isIsland: false
    property int expandedHeightMusic: 200
    property int expandedHeightCalendar: 380
    property int expandedHeightLauncher: 420
    property int expandedHeightSettings: 660
    property int expandedHeightWallpaper: 200
    property int expandedHeightControl: 520

    // Wallpaper (model ported from dynamic-island-hyprland, MIT —
    // see LICENSE-dynamic-island-hyprland.txt)
    property string wallpaperTransitionType: "grow"  // awww transition effect
    property string wallpaperLibraryPath: ""         // "" = default ~/wallpaper + ~/Wallpaper
    property string wallpaperCustomCommand: ""       // "" = built-in awww apply
    property bool enableQuickshellWallpaper: false   // shell draws the background itself
    // Accent tracks the wallpaper: WallpaperService extracts a dominant
    // colour on every wallpaper change while this is on.
    property bool accentFromWallpaper: false

    // Control centre tile grid: 7 columns × 8 rows. Each tile is
    // {id, x, y, w, h} in cells — the settings app edits this array
    // to pick and arrange which controls appear.
    readonly property var defaultControlLayout: [
        { id: "wifi",          x: 0, y: 0, w: 3, h: 1 },
        { id: "focus",         x: 3, y: 0, w: 4, h: 1 },
        { id: "bluetooth",     x: 0, y: 1, w: 3, h: 1 },
        { id: "gamemode",      x: 3, y: 1, w: 3, h: 1 },
        { id: "nightlight",    x: 6, y: 1, w: 1, h: 1 },
        { id: "sound",         x: 0, y: 2, w: 7, h: 1 },
        { id: "display",       x: 0, y: 3, w: 7, h: 1 },
        { id: "notifications", x: 0, y: 4, w: 7, h: 2 },
        { id: "nowplaying",    x: 0, y: 6, w: 7, h: 2 }
    ]
    property var controlLayout: [
        { id: "wifi",          x: 0, y: 0, w: 3, h: 1 },
        { id: "focus",         x: 3, y: 0, w: 4, h: 1 },
        { id: "bluetooth",     x: 0, y: 1, w: 3, h: 1 },
        { id: "gamemode",      x: 3, y: 1, w: 3, h: 1 },
        { id: "nightlight",    x: 6, y: 1, w: 1, h: 1 },
        { id: "sound",         x: 0, y: 2, w: 7, h: 1 },
        { id: "display",       x: 0, y: 3, w: 7, h: 1 },
        { id: "notifications", x: 0, y: 4, w: 7, h: 2 },
        { id: "nowplaying",    x: 0, y: 6, w: 7, h: 2 }
    ]

    // Config file path
    readonly property string configPath: Quickshell.env("HOME") + "/.config/quickshell/settings.conf"

    // Declared as children (not `new`-ed) so they can't be garbage collected
    FileView {
        id: loadFile
        path: root.configPath
        preload: true
        printErrors: false
        onLoaded: root.loadSettings()
    }
    Process { id: saveProc }

    // Load settings on startup (async read completes -> onLoaded fires)
    function loadSettings() {
        var text = loadFile.text();
        if (text) {
            try {
                var obj = JSON.parse(text);
                if (obj.accentColor) root.accentColor = obj.accentColor;
                if (obj.bgBase) root.bgBase = obj.bgBase;
                if (obj.bgSurface) root.bgSurface = obj.bgSurface;
                if (obj.bgOverlay) root.bgOverlay = obj.bgOverlay;
                if (obj.textPrimary) root.textPrimary = obj.textPrimary;
                if (obj.textMuted) root.textMuted = obj.textMuted;
                if (obj.borderColor) root.borderColor = obj.borderColor;
                if (obj.accentGreen) root.accentGreen = obj.accentGreen;
                if (obj.notchWidth !== undefined) root.notchWidth = obj.notchWidth;
                if (obj.notchHeight !== undefined) root.notchHeight = obj.notchHeight;
                if (obj.isIsland !== undefined) root.isIsland = obj.isIsland;
                if (obj.expandedHeightMusic !== undefined) root.expandedHeightMusic = obj.expandedHeightMusic;
                if (obj.expandedHeightCalendar !== undefined) root.expandedHeightCalendar = obj.expandedHeightCalendar;
                if (obj.expandedHeightLauncher !== undefined) root.expandedHeightLauncher = obj.expandedHeightLauncher;
                if (obj.expandedHeightSettings !== undefined) root.expandedHeightSettings = obj.expandedHeightSettings;
                if (obj.expandedHeightWallpaper !== undefined) root.expandedHeightWallpaper = obj.expandedHeightWallpaper;
                if (obj.expandedHeightControl !== undefined) root.expandedHeightControl = obj.expandedHeightControl;
                if (obj.wallpaperTransitionType !== undefined) root.wallpaperTransitionType = obj.wallpaperTransitionType;
                if (obj.wallpaperLibraryPath !== undefined) root.wallpaperLibraryPath = obj.wallpaperLibraryPath;
                if (obj.wallpaperCustomCommand !== undefined) root.wallpaperCustomCommand = obj.wallpaperCustomCommand;
                if (obj.enableQuickshellWallpaper !== undefined) root.enableQuickshellWallpaper = obj.enableQuickshellWallpaper;
                if (obj.accentFromWallpaper !== undefined) root.accentFromWallpaper = obj.accentFromWallpaper;
                if (Array.isArray(obj.controlLayout) && obj.controlLayout.length > 0) root.controlLayout = obj.controlLayout;
            } catch (e) {
                console.warn("Failed to parse settings:", e);
            }
        }
    }

    function saveSettings() {
        var obj = {
            accentColor: String(root.accentColor),
            bgBase: String(root.bgBase),
            bgSurface: String(root.bgSurface),
            bgOverlay: String(root.bgOverlay),
            textPrimary: String(root.textPrimary),
            textMuted: String(root.textMuted),
            borderColor: String(root.borderColor),
            accentGreen: String(root.accentGreen),
            notchWidth: root.notchWidth,
            notchHeight: root.notchHeight,
            isIsland: root.isIsland,
            expandedHeightMusic: root.expandedHeightMusic,
            expandedHeightCalendar: root.expandedHeightCalendar,
            expandedHeightLauncher: root.expandedHeightLauncher,
            expandedHeightSettings: root.expandedHeightSettings,
            expandedHeightWallpaper: root.expandedHeightWallpaper,
            expandedHeightControl: root.expandedHeightControl,
            wallpaperTransitionType: root.wallpaperTransitionType,
            wallpaperLibraryPath: root.wallpaperLibraryPath,
            wallpaperCustomCommand: root.wallpaperCustomCommand,
            enableQuickshellWallpaper: root.enableQuickshellWallpaper,
            accentFromWallpaper: root.accentFromWallpaper,
            controlLayout: root.controlLayout
        };
        var json = JSON.stringify(obj);
        saveProc.command = ["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", json, root.configPath];
        saveProc.running = true;
    }

    // Auto-save when properties change
    onAccentColorChanged: saveSettings()
    onBgBaseChanged: saveSettings()
    onBgSurfaceChanged: saveSettings()
    onBgOverlayChanged: saveSettings()
    onTextPrimaryChanged: saveSettings()
    onTextMutedChanged: saveSettings()
    onBorderColorChanged: saveSettings()
    onAccentGreenChanged: saveSettings()
    onNotchWidthChanged: saveSettings()
    onNotchHeightChanged: saveSettings()
    onIsIslandChanged: saveSettings()
    onExpandedHeightMusicChanged: saveSettings()
    onExpandedHeightCalendarChanged: saveSettings()
    onExpandedHeightLauncherChanged: saveSettings()
    onExpandedHeightSettingsChanged: saveSettings()
    onExpandedHeightWallpaperChanged: saveSettings()
    onExpandedHeightControlChanged: saveSettings()
    onWallpaperTransitionTypeChanged: saveSettings()
    onWallpaperLibraryPathChanged: saveSettings()
    onWallpaperCustomCommandChanged: saveSettings()
    onEnableQuickshellWallpaperChanged: saveSettings()
    onAccentFromWallpaperChanged: saveSettings()
    onControlLayoutChanged: saveSettings()
}