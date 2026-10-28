pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper engine: directory scan with a 640x360 thumbnail cache, backend
// aware applying (awww / swww / hyprpaper, overridable via
// ~/.config/quickshell/wallpaper_backend) and the transition / library /
// custom-command settings.
//
// Scan, thumbnail-hash and backend-detection logic adapted from
// dynamic-island-hyprland (c) St0rmosu, MIT — see
// LICENSE-dynamic-island-hyprland.txt in this directory.
Singleton {
    id: root

    property list<string> wallpapers: []
    // path -> cached 640x360 thumbnail; entries appear as they are generated
    // (empty/missing = fall back to the full-size original)
    property var thumbs: ({})
    // Staged rescan: the fresh listing accumulates here and is swapped in
    // whole when the scan finishes, so re-opening the picker never flashes
    // the strip empty.
    property bool scanStaging: false
    property var stagedWallpapers: []
    property var stagedThumbs: ({})
    property string currentWallpaper: ""
    property string backend: "awww"

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string cacheDir: homeDir + "/.cache/quickshell/wallpaper-picker"
    readonly property string scanScript:
        homeDir + "/.config/quickshell/scripts/scan_wallpapers.py"

    // Library folders: the settings-app path when set, otherwise the
    // classic pair of wallpaper directories.
    readonly property var scanDirs: {
        const lib = SettingsService.wallpaperLibraryPath.trim();
        if (lib !== "") return [lib];
        return [homeDir + "/wallpaper", homeDir + "/Wallpaper"];
    }

    // Thumbnail for a wallpaper — the cached thumb when ready, the
    // full-size original while it is still being generated.
    function thumbFor(path) {
        if (path === "" || path === undefined) return "";
        const t = thumbs[path];
        return (t !== undefined && t !== null && t !== "") ? t : path;
    }

    // ── Scan: python script streams JSON records on stdout ──
    Process {
        id: scanner
        running: false
        command: ["python3", root.scanScript, root.cacheDir]
        stdout: SplitParser {
            onRead: line => {
                if (line === "") return;
                try {
                    const rec = JSON.parse(line);
                    if (rec.path !== undefined) {
                        if (root.scanStaging) {
                            root.stagedWallpapers.push(rec.path);
                            if (rec.thumb !== undefined && rec.thumb !== "")
                                root.stagedThumbs[rec.path] = rec.thumb;
                        } else {
                            root.wallpapers = [...root.wallpapers, rec.path];
                            if (rec.thumb !== undefined && rec.thumb !== "")
                                root.thumbs = Object.assign({}, root.thumbs, { [rec.path]: rec.thumb });
                        }
                    } else if (rec.ready !== undefined) {
                        if (root.scanStaging)
                            root.stagedThumbs[rec.ready] = rec.thumb;
                        else
                            root.thumbs = Object.assign({}, root.thumbs, { [rec.ready]: rec.thumb });
                    }
                } catch (e) { /* partial line or non-JSON noise */ }
            }
        }
        // A staged scan publishes its listing in one go on exit.  A killed
        // run may also report exit while a newer one is already going —
        // then the staging belongs to the new run, so leave it alone.
        onExited: () => {
            if (root.scanStaging && !scanner.running) {
                root.scanStaging = false;
                root.wallpapers = root.stagedWallpapers;
                root.thumbs = Object.assign({}, root.stagedThumbs);
            }
        }
    }

    // ── Backend detection: config file override, else first tool found ──
    Process {
        id: backendDetect
        running: false
        command: ["sh", "-c",
            'f="$HOME/.config/quickshell/wallpaper_backend"; ' +
            'if [ -f "$f" ]; then tr -d " \\n\\r" < "$f"; exit 0; fi; ' +
            'command -v awww-daemon >/dev/null && { echo awww; exit; }; ' +
            'command -v swww >/dev/null && { echo swww; exit; }; ' +
            'command -v hyprpaper >/dev/null && { echo hyprpaper; exit; }; ' +
            'echo awww']
        stdout: SplitParser {
            onRead: line => {
                const b = line.trim();
                if (b !== "") root.backend = b;
            }
        }
    }

    // Load saved wallpaper path; re-apply it on startup (login/restart)
    FileView {
        id: configFile
        path: root.homeDir + "/.config/quickshell/wallpaper.conf"
        preload: true
        printErrors: false
        onTextChanged: {
            const saved = configFile.text().trim();
            if (saved !== "" && saved !== root.currentWallpaper) {
                root.currentWallpaper = saved;
                root.applyToDesktop(saved);
            }
        }
    }

    Component.onCompleted: {
        backendDetect.running = true;
        scanner.command = ["python3", root.scanScript, root.cacheDir, ...root.scanDirs];
        scanner.running = true;
    }

    function rescan() {
        stagedWallpapers = [];
        stagedThumbs = {};
        scanStaging = true;
        scanner.running = false;
        scanner.command = ["python3", root.scanScript, root.cacheDir, ...root.scanDirs];
        scanner.running = true;
    }

    function setWallpaper(path) {
        currentWallpaper = path;
        applyToDesktop(path);

        // Save to config
        saveProcess.command = ["sh", "-c", 'printf "%s" "$1" > "$HOME/.config/quickshell/wallpaper.conf"', "sh", path];
        saveProcess.running = true;
    }

    function applyToDesktop(path) {
        const custom = SettingsService.wallpaperCustomCommand.trim();
        if (custom !== "") {
            // User command gets the file as $1 (upstream convention)
            setProcess.command = ["sh", "-c", custom, "wallpaper-apply", path];
        } else {
            const t = SettingsService.wallpaperTransitionType.trim() || "grow";
            switch (backend) {
            case "swww":
                setProcess.command = ["swww", "img", path,
                    "--transition-type", t,
                    "--transition-pos", "center",
                    "--transition-duration", "1",
                    "--transition-fps", "60"];
                break;
            case "hyprpaper":
                setProcess.command = ["sh", "-c",
                    'mon=$(hyprctl -j monitors 2>/dev/null | ' +
                    'python3 -c \'import json,sys;print(json.load(sys.stdin)[0]["name"])\' 2>/dev/null); ' +
                    '[ -n "$mon" ] || exit 0; ' +
                    'hyprctl hyprpaper preload "$1" >/dev/null 2>&1; ' +
                    'hyprctl hyprpaper "$mon" "$1" >/dev/null 2>&1',
                    "wallpaper-apply", path];
                break;
            default: // awww
                setProcess.command = ["awww", "img", path,
                    "--transition-type", t,
                    "--transition-pos", "center",
                    "--transition-duration", "1",
                    "--transition-fps", "60"];
            }
        }
        setProcess.running = false;
        setProcess.running = true;
    }

    function nextWallpaper() {
        if (wallpapers.length === 0) return;
        const idx = wallpapers.indexOf(currentWallpaper);
        const nextIdx = (idx + 1) % wallpapers.length;
        setWallpaper(wallpapers[nextIdx]);
    }

    function prevWallpaper() {
        if (wallpapers.length === 0) return;
        const idx = wallpapers.indexOf(currentWallpaper);
        const prevIdx = idx <= 0 ? wallpapers.length - 1 : idx - 1;
        setWallpaper(wallpapers[prevIdx]);
    }

    Process {
        id: setProcess
        command: []
        running: false
    }

    Process {
        id: saveProcess
        command: []
        running: false
    }

    // ── Accent from wallpaper ──
    // Picks a dominant, saturated colour from the current wallpaper and
    // feeds it to SettingsService.accentColor while the setting is on.
    readonly property string accentScript:
        homeDir + "/.config/quickshell/scripts/accent_from_wallpaper.py"

    function refreshAccent() {
        if (!SettingsService.accentFromWallpaper || currentWallpaper === "")
            return;
        accentProc.running = false;
        accentProc.command = ["python3", accentScript, currentWallpaper];
        accentProc.running = true;
    }

    onCurrentWallpaperChanged: refreshAccent()

    // The setting and the wallpaper path load from separate async
    // FileViews at startup: whichever lands last triggers the extraction.
    // This late check covers the case where both land "already set".
    Timer {
        interval: 1500
        running: SettingsService.accentFromWallpaper
        onTriggered: root.refreshAccent()
    }

    Connections {
        target: SettingsService
        function onAccentFromWallpaperChanged() { root.refreshAccent(); }
    }

    Process {
        id: accentProc
        command: []
        running: false
        stdout: SplitParser {
            onRead: line => {
                const hex = line.trim();
                if (/^#[0-9a-fA-F]{6}$/.test(hex))
                    SettingsService.accentColor = hex;
            }
        }
    }
}
