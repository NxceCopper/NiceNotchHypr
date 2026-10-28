pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Quick toggles for the control center tiles:
//   Focus      — do not disturb (gates notification popups)
//   Game Mode  — disables Hyprland animations, blur and corner rounding,
//                and turns Focus on for as long as it is active
//   Night Light— warm screen via hyprsunset (needs `pacman -S hyprsunset`)
Singleton {
    id: root

    property bool dnd: false
    property bool gameMode: false
    property bool nightLight: false
    property int temperature: 3500    // Night Light colour temp in kelvin
    property bool _restarting: false  // set while cycling hyprsunset for a temp change

    // Values saved before Game Mode kicks in, restored when it turns off
    property bool _savedAnim: true
    property bool _savedBlur: true
    property int _savedRound: 30
    property bool _dndBeforeGame: false

    // Persisted so a quickshell reload cannot leave Hyprland de-animated
    // while the tile claims Game Mode is off (and resumes night light).
    readonly property string statePath: Quickshell.env("HOME") + "/.config/quickshell/toggles.conf"

    FileView {
        id: stateFile
        path: root.statePath
        preload: true
        printErrors: false
        onLoaded: root.loadState()
    }
    Process { id: stateSaveProc }

    property bool _loading: false

    function loadState() {
        var text = stateFile.text();
        if (!text) return;
        _loading = true;
        try {
            var o = JSON.parse(text);
            if (o.dnd !== undefined) dnd = o.dnd;
            if (o._savedAnim !== undefined) _savedAnim = o._savedAnim;
            if (o._savedBlur !== undefined) _savedBlur = o._savedBlur;
            if (o._savedRound !== undefined) _savedRound = o._savedRound;
            if (o._dndBeforeGame !== undefined) _dndBeforeGame = o._dndBeforeGame;
            if (o.temperature !== undefined) temperature = o.temperature;
            if (o.nightLight === true) setNightLight(true);
            if (o.gameMode === true) {
                gameMode = true;
                dnd = true;
                applyProc.command = ["hyprctl", "eval", lua(false)];
                applyProc.running = true;
            }
        } catch (e) {
            console.warn("TogglesService: failed to parse state:", e);
        }
        _loading = false;
    }

    function saveState() {
        if (_loading) return;
        var o = {
            dnd: dnd,
            gameMode: gameMode,
            nightLight: nightLight,
            _savedAnim: _savedAnim,
            _savedBlur: _savedBlur,
            _savedRound: _savedRound,
            _dndBeforeGame: _dndBeforeGame,
            temperature: temperature
        };
        var json = JSON.stringify(o);
        stateSaveProc.command = ["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", json, root.statePath];
        stateSaveProc.running = true;
    }

    onDndChanged: saveState()
    onGameModeChanged: saveState()
    onNightLightChanged: saveState()

    // ── Focus ─────────────────────────────────────────────────────────────
    function setDnd(on) {
        dnd = on;
    }

    function toggleDnd() {
        setDnd(!dnd);
    }

    // ── Game Mode ─────────────────────────────────────────────────────────
    function setGameMode(on) {
        if (on === gameMode) return;
        if (on) {
            _dndBeforeGame = dnd;
            gameMode = true;
            dnd = true;
            saveProc.command = ["sh", "-c",
                "hyprctl getoption animations:enabled -j; " +
                "hyprctl getoption decoration:blur:enabled -j; " +
                "hyprctl getoption decoration:rounding -j"];
            saveProc.running = true;
        } else {
            gameMode = false;
            dnd = _dndBeforeGame;
            applyProc.command = ["hyprctl", "eval", lua(true)];
            applyProc.running = true;
        }
    }

    function toggleGameMode() {
        setGameMode(!gameMode);
    }

    // Hyprland's Lua config rejects `keyword` — settings go through eval.
    // restore=true puts back the saved values, otherwise game mode kicks in.
    function lua(restore) {
        var anim = restore ? _savedAnim : false;
        var blur = restore ? _savedBlur : false;
        var round = restore ? _savedRound : 0;
        return "hl.config({ animations = { enabled = " + anim + " }, "
             + "decoration = { blur = { enabled = " + blur + " }, "
             + "rounding = " + round + " } })";
    }

    // Parse the three saved options, then apply the game-mode settings
    Process {
        id: saveProc
        stdout: SplitParser {
            onRead: line => {
                try {
                    var o = JSON.parse(line);
                    if (o.option === "animations:enabled") root._savedAnim = o.bool;
                    else if (o.option === "decoration:blur:enabled") root._savedBlur = o.bool;
                    else if (o.option === "decoration:rounding") root._savedRound = o.int;
                } catch (e) {
                    console.warn("TogglesService: bad getoption output:", e, line);
                }
            }
        }
        onExited: {
            applyProc.command = ["hyprctl", "eval", root.lua(false)];
            applyProc.running = true;
            root.saveState(); // persist the freshly read _saved* values
        }
    }

    Process { id: applyProc }

    // ── Night Light ───────────────────────────────────────────────────────
    // hyprsunset restores the gamma itself when it is killed
    Process {
        id: nightProc
        command: ["hyprsunset", "-t", String(root.temperature)]
        onExited: (code) => {
            if (root._restarting) { root._restarting = false; return; }
            if (root.nightLight) {
                root.nightLight = false;
                if (code !== 0)
                    console.warn("TogglesService: hyprsunset exited (" + code +
                                 ") — install it with: pacman -S hyprsunset");
            }
        }
    }

    // A failed start (missing binary) never emits exited, so probe first
    property bool nightLightAvailable: true

    Process {
        id: nightCheckProc
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: (code) => {
            root.nightLightAvailable = (code === 0);
            if (!nightLightAvailable)
                console.warn("TogglesService: hyprsunset not installed — Night Light unavailable. Install: pacman -S hyprsunset");
        }
    }

    Component.onCompleted: nightCheckProc.running = true

    function setNightLight(on) {
        if (on === nightLight) return;
        if (on) {
            if (!nightLightAvailable) {
                console.warn("TogglesService: Night Light needs hyprsunset — install: pacman -S hyprsunset");
                return;
            }
            nightLight = true;
            nightProc.running = true;
            nlVerify.restart();
        } else {
            nightLight = false;
            nightProc.running = false; // kills hyprsunset, gamma restored
        }
    }

    // A missing binary fails before `exited` fires — catch it right after start
    Timer {
        id: nlVerify
        interval: 400
        onTriggered: {
            if (root.nightLight && !nightProc.running) {
                root.nightLight = false;
                root.nightLightAvailable = false;
                console.warn("TogglesService: hyprsunset failed to start — install: pacman -S hyprsunset");
            }
        }
    }

    function toggleNightLight() {
        setNightLight(!nightLight);
    }

    // Warmth slider: persist and, if Night Light is running, cycle hyprsunset
    function setTemperature(k) {
        k = Math.max(2500, Math.min(6500, Math.round(k)));
        if (k === temperature) return;
        temperature = k;
        saveState();
        if (!nightLight || !nightLightAvailable) return;
        _restarting = true;
        nightProc.running = false;                 // killed on purpose
        nightProc.command = ["hyprsunset", "-t", String(k)];
        nightProc.running = true;
        nlVerify.restart();
    }
}
