// Ported from dynamic-island-hyprland (St0rmosu), MIT License — see
// LICENSE-dynamic-island-hyprland.txt. Adapted: hyprctl -j snapshots via a
// single sequential Process instead of upstream's C++ SystemServices.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: root

    visible: false

    property var windowList: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var activeWorkspace: null
    property var monitors: []
    property bool clientsReady: false
    property bool monitorsReady: false
    property bool workspacesReady: false
    property bool activeWorkspaceReady: false
    property bool clientsRefreshPending: false
    property bool monitorsRefreshPending: false
    property bool workspacesRefreshPending: false
    property bool activeWorkspaceRefreshPending: false
    property string currentSnapshot: ""
    property string snapshotBuffer: ""
    readonly property bool ready: clientsReady && monitorsReady && workspacesReady && activeWorkspaceReady

    function resolveWsId(ws) {
        if (!ws) return 1;
        if (typeof ws === "number") return ws > 0 ? ws : 1;
        if (ws.name !== undefined) {
            const parsed = parseInt(ws.name);
            if (!isNaN(parsed) && parsed > 0) return parsed;
        }
        if (ws.address !== undefined) {
            const parsed = parseInt(ws.address);
            if (!isNaN(parsed) && parsed > 0) return parsed;
        }
        if (ws.id !== undefined) {
            const parsed = parseInt(ws.id);
            if (!isNaN(parsed) && parsed > 0) return parsed;
        }
        return 1;
    }

    function parseJson(text, fallback) {
        const source = String(text === undefined || text === null ? "" : text).trim();
        if (source === "")
            return fallback;

        try {
            return JSON.parse(source);
        } catch (error) {
            console.log("[HyprlandData] Failed to parse snapshot:", error);
            return fallback;
        }
    }

    function rebuildWindowIndex() {
        const byAddress = {};
        for (let index = 0; index < root.windowList.length; index++)
            byAddress[String(root.windowList[index].address || "").toLowerCase()] = root.windowList[index];
        root.windowByAddress = byAddress;
    }

    function requestRefresh(refreshClients, refreshMonitors, refreshWorkspaces, refreshActiveWorkspace, immediate) {
        clientsRefreshPending = clientsRefreshPending || refreshClients;
        monitorsRefreshPending = monitorsRefreshPending || refreshMonitors;
        workspacesRefreshPending = workspacesRefreshPending || refreshWorkspaces;
        activeWorkspaceRefreshPending = activeWorkspaceRefreshPending || refreshActiveWorkspace;

        if (immediate) {
            refreshTimer.stop();
            flushRefresh();
        } else {
            refreshTimer.restart();
        }
    }

    function queueRefresh(refreshClients, refreshMonitors, refreshWorkspaces, refreshActiveWorkspace) {
        requestRefresh(refreshClients, refreshMonitors, refreshWorkspaces, refreshActiveWorkspace, false);
    }

    function updateAll() {
        requestRefresh(true, true, true, true, true);
    }

    function flushRefresh() {
        // One hyprctl -j snapshot at a time; requeues itself on exit.
        if (snapshotProc.running || currentSnapshot !== "")
            return;

        let next = "";
        let endpoint = "";
        if (clientsRefreshPending) {
            clientsRefreshPending = false;
            next = "clients";
        } else if (monitorsRefreshPending) {
            monitorsRefreshPending = false;
            next = "monitors";
        } else if (workspacesRefreshPending) {
            workspacesRefreshPending = false;
            next = "workspaces";
        } else if (activeWorkspaceRefreshPending) {
            activeWorkspaceRefreshPending = false;
            next = "activeWorkspace";
        }
        if (next === "")
            return;

        currentSnapshot = next;
        endpoint = next === "activeWorkspace" ? "activeworkspace" : next;
        snapshotBuffer = "";
        snapshotProc.command = ["hyprctl", "-j", endpoint];
        snapshotProc.running = true;
    }

    function queueRefreshForEvent(event) {
        if (!event || !event.name)
            return;

        const name = String(event.name);
        if (["openlayer", "closelayer", "screencast"].indexOf(name) !== -1)
            return;

        if (name === "configreloaded") {
            queueRefresh(true, true, true, true);
            return;
        }

        const affectsActiveWorkspace = name === "workspace"
            || name === "workspacev2"
            || name === "focusedmon"
            || name === "focusedmonv2";
        const affectsWorkspaces = affectsActiveWorkspace
            || name.indexOf("workspace") !== -1;
        const affectsMonitors = name.indexOf("monitor") !== -1
            || name === "focusedmon"
            || name === "focusedmonv2";
        const affectsClients = name.indexOf("window") !== -1
            || name === "changefloatingmode"
            || name === "fullscreen"
            || name === "pin"
            || name === "urgent"
            || name === "minimize"
            || name === "moveintogroup"
            || name === "moveoutofgroup"
            || name === "togglegroup";

        if (!affectsClients && !affectsMonitors && !affectsWorkspaces && !affectsActiveWorkspace)
            return;

        queueRefresh(affectsClients, affectsMonitors, affectsWorkspaces, affectsActiveWorkspace);
    }

    Component.onCompleted: updateAll()
    Component.onDestruction: {
        refreshTimer.stop();
    }

    Timer {
        id: refreshTimer

        interval: 90
        repeat: false

        onTriggered: root.flushRefresh()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            root.queueRefreshForEvent(event);
        }
    }

    Process {
        id: snapshotProc
        running: false

        stdout: SplitParser {
            onRead: function(data) {
                root.snapshotBuffer += data;
            }
        }

        onExited: function(code) {
            if (code === 0)
                root.applySnapshot(root.currentSnapshot, root.snapshotBuffer);
            else
                console.log("[HyprlandData] hyprctl snapshot failed:", root.currentSnapshot, code);
            root.snapshotBuffer = "";
            root.currentSnapshot = "";
            root.flushRefresh();
        }
    }

    function applySnapshot(subject, payloadJson) {
        if (subject === "clients") {
            const list = root.parseJson(payloadJson, []);
            for (let i = 0; i < list.length; i++) {
                const win = list[i];
                if (win && win.workspace) {
                    win.workspace.id = root.resolveWsId(win.workspace);
                }
            }
            root.windowList = list;
            root.rebuildWindowIndex();
            root.clientsReady = true;
        } else if (subject === "monitors") {
            const mons = root.parseJson(payloadJson, []);
            for (let i = 0; i < mons.length; i++) {
                const m = mons[i];
                if (m && m.activeWorkspace) {
                    m.activeWorkspace.id = root.resolveWsId(m.activeWorkspace);
                }
            }
            root.monitors = mons;
            root.monitorsReady = true;
        } else if (subject === "workspaces") {
            const rawWorkspaces = root.parseJson(payloadJson, []);
            for (let i = 0; i < rawWorkspaces.length; i++) {
                const ws = rawWorkspaces[i];
                if (ws) {
                    ws.id = root.resolveWsId(ws);
                }
            }
            root.workspaces = rawWorkspaces.filter((workspace) => workspace.id >= 1 && workspace.id <= 100);
            root.workspacesReady = true;
        } else if (subject === "activeWorkspace") {
            const aw = root.parseJson(payloadJson, null);
            if (aw) {
                aw.id = root.resolveWsId(aw);
            }
            root.activeWorkspace = aw;
            root.activeWorkspaceReady = true;
        }
    }
}
