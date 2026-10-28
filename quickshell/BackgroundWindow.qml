import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Shell-drawn desktop background, on the bottom layer underneath everything.
// Static (no awww transition) — leave it off in settings to keep the native
// awww animations; enable it to have quickshell own the wallpaper instead
// (useful when no wallpaper daemon is running).
//
// Ported from dynamic-island-hyprland (c) St0rmosu, MIT — see
// LICENSE-dynamic-island-hyprland.txt in this directory.
PanelWindow {
    id: bgWindow

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:background"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    readonly property string homeDir: Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")

    // pywal's cache as a fallback source (upstream behaviour) for setups
    // that keep the active wallpaper there instead of in wallpaper.conf
    FileView {
        id: walFile
        path: bgWindow.homeDir + "/.cache/wal/wal"
        watchChanges: true
        preload: true
        printErrors: false
        property string wallpaper: ""
        Component.onCompleted: reload()
        onFileChanged: reload()
        onLoaded: wallpaper = text().trim()
    }

    readonly property string effectiveWallpaperPath: {
        if (WallpaperService.currentWallpaper !== "")
            return WallpaperService.currentWallpaper;
        return walFile.wallpaper;
    }

    readonly property string effectiveWallpaperUrl: {
        const wp = effectiveWallpaperPath;
        if (wp === "") return "";
        return wp.startsWith("file://") ? wp : ("file://" + encodeURI(wp));
    }

    visible: SettingsService.enableQuickshellWallpaper && effectiveWallpaperUrl !== ""

    Image {
        id: bgImage
        anchors.fill: parent
        source: bgWindow.effectiveWallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true

        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }
    }
}
