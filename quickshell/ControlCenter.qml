import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// Control centre inside the expanded notch pill — a 7 × 8 tile grid
// matched against the brief's walkthrough screenshots:
//   row 0  Wi-Fi (3) ┃ Focus / DND (4)
//   row 1  Bluetooth (3) ┃ Game Mode (3) ┃ Night Light round (1)
//   row 2  Sound   — full-width slider card
//   row 3  Display — full-width slider card
//   row 4–5 Notifications (7 × 2)
//   row 6–7 Now playing (7 × 2) — blurred art, transport, progress
// Tile placement comes from SettingsService.controlLayout so the settings
// app can pick and rearrange controls later.
// Colours are sampled from the reference (near-black cards on a pure black
// panel, recessed wells, raised notification rows); only the accent comes
// from the user's theme so it stays consistent with the rest of the shell.
//
// Interaction: the round button of a capsule toggles that radio, the rest of
// the capsule drops down a list of nearby networks / devices.
//
// Opened via SUPER+SHIFT+P. Esc closes the list first, then the panel.
Item {
    id: root

    // NotificationServer lives in shell.qml (must always run) and is passed in
    property var notifs: null
    property int focusAttempts: 0

    // System state
    property bool wifiOn: false
    property string ssid: ""
    property string sinkName: ""       // default output device description
    property bool btOn: false
    property int btCount: 0
    property bool muted: false
    property int bMax: 0
    property real pendingVol: 0
    property real pendingBright: 0
    property int pendingTemp: 3500     // Night Light warmth while dragging

    // ── Reference palette (sampled from the example) ──
    readonly property color cardBg: "#141211"      // card surface
    readonly property color wellBg: "#0b0907"      // recessed slider wells
    readonly property color rowBg: Qt.rgba(1, 1, 1, 0.055)  // notification rows
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.07)

    // ── Drop-down lists ──
    property string subPage: ""       // "", "sound", "display" — full sub-pages
    property string openMenu: ""      // "", "wifi", "bt" — tile drop-down menus
    property var wifiNets: []
    property var btDevs: []
    property bool wifiScanning: false
    property bool btScanning: false
    property var _wifiBuf: []
    property var _btBuf: []
    property var _btConn: ({})
    property var _btSeen: ({})
    property int _btPhase: 0

    signal dismissed()

    // ── Geometry: 7 columns × 8 rows, scaled to the panel ──
    readonly property int gap: 10
    readonly property real contentW: width - 20
    readonly property real contentH: height - 20
    readonly property real cellW: (contentW - 6 * gap) / 7
    // Cell height is pinned to the height slider, not to the panel's own
    // height: the panel shrinks to the rows in use while tiles keep their size.
    readonly property real cellH: (SettingsService.expandedHeightControl - 90) / 8

    function cellX(c) { return 10 + c * (cellW + gap) }
    function cellY(r) { return 10 + r * (cellH + gap) }
    function spanW(n) { return n * cellW + (n - 1) * gap }
    function spanH(n) { return n * cellH + (n - 1) * gap }

    // Tile placement from the persisted layout; unknown ids collapse away
    function tile(id) {
        var l = SettingsService.controlLayout;
        for (var i = 0; i < l.length; i++)
            if (l[i].id === id) return l[i];
        return null;
    }
    function hasTile(id) { return tile(id) !== null; }
    function tx(id) { var t = tile(id); return t ? cellX(t.x) : 0; }
    function ty(id) { var t = tile(id); return t ? cellY(t.y) : 0; }
    function tw(id) { var t = tile(id); return t ? spanW(t.w) : 0; }
    function th(id) { var t = tile(id); return t ? spanH(t.h) : 0; }

    // ── Open: refresh everything and grab Esc focus ──
    onVisibleChanged: {
        if (!visible) {
            subPage = "";
            openMenu = "";
            return;
        }
        focusAttempts = 0;
        refreshAll()
        Qt.callLater(function () { root.forceActiveFocus() })
        focusRetry.restart()
    }

    Keys.onEscapePressed: event => {
        if (root.openMenu !== "") {
            root.openMenu = "";
            event.accepted = true;
        } else if (root.subPage !== "") {
            root.subPage = "";
            event.accepted = true;
        } else {
            root.dismissed();
        }
    }

    Timer {
        id: focusRetry
        interval: 100
        repeat: true
        onTriggered: {
            if (!root.visible || root.activeFocus) {
                stop()
                return
            }
            if (++root.focusAttempts > 8) {
                stop()
                return
            }
            root.forceActiveFocus()
        }
    }

    // Keep volume/brightness/wifi states live while the panel is open
    Timer {
        interval: 1500
        repeat: true
        running: root.visible
        onTriggered: root.refreshAll()
    }

    // ── Processes ──────────────────────────────────────────────────────────
    Process {
        id: wifiRead
        command: ["sh", "-c", "nmcli -t -f WIFI g; nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:' | head -1 | cut -d: -f2-"]
        stdout: SplitParser {
            onRead: line => {
                line = line.trim();
                if (line === "enabled" || line === "disabled") root.wifiOn = line === "enabled";
                else if (line !== "") root.ssid = line;
            }
        }
    }

    Process {
        id: wifiWrite
        command: []
    }

    Process {
        id: btRead
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | awk '/Powered/{print $2}'; bluetoothctl devices Connected 2>/dev/null | grep -c '^Device'"]
        stdout: SplitParser {
            onRead: line => {
                line = line.trim();
                if (line === "yes" || line === "no") root.btOn = line === "yes";
                else if (/^[0-9]+$/.test(line)) root.btCount = parseInt(line);
            }
        }
    }

    Process {
        id: btWrite
        command: []
    }

    Process {
        id: volRead
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/Volume:\s*([0-9.]+)/);
                if (m) {
                    root.muted = line.indexOf("[MUTED]") !== -1;
                    if (!volSlider.dragging) volSlider.value = Math.min(1, parseFloat(m[1]));
                }
            }
        }
    }

    Process {
        id: volWrite
        command: []
    }

    Process {
        id: muteWrite
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
    }

    Process {
        id: brightRead
        command: ["sh", "-c", 'd=$(basename $(ls -d /sys/class/backlight/* 2>/dev/null | head -1)); b=$(cat /sys/class/backlight/*/brightness 2>/dev/null); m=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null); echo "$d ${b:-0} ${m:-0}"']
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim().split(/\s+/);
                if (t.length >= 3 && t[0] !== "") {
                    var b = parseInt(t[1]);
                    var m = parseInt(t[2]);
                    if (m > 0) {
                        root.bMax = m;
                        if (!brightSlider.dragging) brightSlider.value = Math.min(1, b / m);
                    }
                }
            }
        }
    }

    Process {
        id: brightWrite
        command: []
    }

    // Brightness needs the logind session; resolves the path and device inline
    function brightnessCommand(v) {
        return ["sh", "-c",
            "s=\"$XDG_SESSION_ID\"; " +
            "if [ -z \"$s\" ]; then s=$(loginctl 2>/dev/null | awk -v u=\"$USER\" '$3==u && $4==\"seat0\" {id=$1} END{print id}'); fi; " +
            "p=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager GetSession s \"$s\" 2>/dev/null | sed -n 's/.*\"\\(.*\\)\".*/\\1/p'); " +
            "d=$(basename $(ls -d /sys/class/backlight/* 2>/dev/null | head -1)); " +
            "[ -n \"$p\" ] && [ -n \"$d\" ] && busctl call org.freedesktop.login1 \"$p\" org.freedesktop.login1.Session SetBrightness ssu backlight \"$d\" " + v];
    }

    Timer {
        id: volDebounce
        interval: 90
        onTriggered: {
            volWrite.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.round(root.pendingVol * 100) + "%"];
            volWrite.running = true;
        }
    }

    Timer {
        id: brightDebounce
        interval: 90
        onTriggered: {
            brightWrite.command = root.brightnessCommand(Math.round(root.pendingBright * root.bMax));
            brightWrite.running = true;
        }
    }

    Timer {
        id: tempDebounce
        interval: 250
        onTriggered: TogglesService.setTemperature(root.pendingTemp)
    }

    // Default output device name for the Sound page
    Process {
        id: sinkRead
        command: ["sh", "-c", "wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'\"' '/node.description/{print $2; exit}'"]
        stdout: SplitParser {
            onRead: line => {
                line = line.trim();
                if (line !== "") root.sinkName = line;
            }
        }
    }

    // ── Network / device discovery (drives the drop-downs) ────────────────
    Process {
        id: wifiScan
        command: ["sh", "-c", "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan yes 2>/dev/null"]
        stdout: SplitParser { onRead: line => root.parseWifiLine(line) }
        onExited: () => {
            root.wifiNets = root._wifiBuf;
            root.wifiScanning = false;
        }
    }

    Process {
        id: btScan
        command: ["sh", "-c",
            // bluetoothctl exits at once — discovery keeps running on the
            // controller, so wait before listing devices
            "bluetoothctl scan on >/dev/null 2>&1; " +
            "sleep 3; " +
            "echo '@@conn'; bluetoothctl devices Connected 2>/dev/null; " +
            "echo '@@all'; bluetoothctl devices 2>/dev/null; " +
            "bluetoothctl scan off >/dev/null 2>&1"]
        stdout: SplitParser { onRead: line => root.parseBtLine(line) }
        onExited: () => {
            root.btDevs = root._btBuf;
            root.btScanning = false;
        }
    }

    Process {
        id: wifiAct
        command: []
        onExited: rescanTimer.restart()
    }

    Process {
        id: btAct
        command: []
        onExited: rescanTimer.restart()
    }

    Timer {
        id: rescanTimer
        interval: 1400
        onTriggered: {
            root.refreshAll();
            if (root.openMenu === "wifi") root.scanWifi();
            else if (root.openMenu === "bt") root.scanBt();
        }
    }

    function parseWifiLine(line) {
        line = line.trim();
        if (line === "") return;
        // nmcli terse mode escapes ':' and ';' inside values
        var t = line.replace(/\\:/g, "\u0001").replace(/\\\;/g, "\u0002").split(":");
        if (t.length < 4) return;
        var security = t[t.length - 1];
        var signal = parseInt(t[t.length - 2]);
        if (isNaN(signal)) return;
        var ssid = t.slice(1, t.length - 2).join(":")
            .replace(/\u0001/g, ":").replace(/\u0002/g, ";");
        if (ssid === "") return;
        root._wifiBuf.push({
            ssid: ssid,
            signal: signal,
            secure: security !== "--" && security !== "",
            active: t[0] === "*"
        });
    }

    function parseBtLine(line) {
        line = line.trim();
        if (line === "@@conn") { root._btPhase = 1; return; }
        if (line === "@@all") { root._btPhase = 2; return; }
        var m = line.match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$/);
        if (!m) return;
        var mac = m[1].toUpperCase();
        var name = m[2];
        if (root._btPhase === 1) {
            if (root._btConn[mac]) return;
            root._btConn[mac] = true;
            root._btBuf.push({ mac: mac, name: name, connected: true });
        } else {
            if (root._btSeen[mac] || root._btConn[mac]) return;
            root._btSeen[mac] = true;
            root._btBuf.push({ mac: mac, name: name, connected: false });
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────
    function refreshAll() {
        if (!wifiRead.running) wifiRead.running = true;
        if (!btRead.running) btRead.running = true;
        if (!volRead.running) volRead.running = true;
        if (!brightRead.running) brightRead.running = true;
    }

    function toggleWifi() {
        wifiWrite.command = ["nmcli", "radio", "wifi", wifiOn ? "off" : "on"];
        wifiWrite.running = true;
        wifiOn = !wifiOn;
        if (!wifiOn) {
            ssid = "";
            openMenu = "";
        } else if (openMenu === "wifi") {
            wifiScanDelay.restart();
        }
    }

    function toggleBt() {
        btWrite.command = ["bluetoothctl", "power", btOn ? "off" : "on"];
        btWrite.running = true;
        btOn = !btOn;
        if (!btOn) {
            btCount = 0;
            openMenu = "";
        } else if (openMenu === "bt") {
            scanBt();
        }
    }

    function toggleMute() {
        muteWrite.running = true;
        muted = !muted;
    }

    function openSub(name) {
        subPage = (subPage === name) ? "" : name;
    }

    // Tile drop-downs (wifi / bt) are exclusive with the full sub-pages
    function toggleMenu(which) {
        subPage = "";
        openMenu = (openMenu === which) ? "" : which;
        if (openMenu === "wifi") wifiScanDelay.restart();   // let refreshAll's nmcli finish first
        else if (openMenu === "bt") scanBt();
    }

    onSubPageChanged: {
        if (subPage === "sound") sinkRead.running = true;
    }

    Timer {
        id: wifiScanDelay
        interval: 450
        onTriggered: if (root.openMenu === "wifi") root.scanWifi()
    }

    function scanWifi() {
        if (!wifiOn) {
            wifiNets = [];
            wifiScanning = false;
            return;
        }
        _wifiBuf = [];
        wifiScanning = true;
        if (!wifiScan.running) wifiScan.running = true;
    }

    function scanBt() {
        if (!btOn) {
            btDevs = [];
            btScanning = false;
            return;
        }
        _btBuf = [];
        _btConn = ({});
        _btSeen = ({});
        _btPhase = 0;
        btScanning = true;
        if (!btScan.running) btScan.running = true;
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    function wifiAction(net) {
        if (net.active) wifiAct.command = ["sh", "-c", "nmcli connection down id " + shq(net.ssid)];
        else wifiAct.command = ["sh", "-c", "nmcli device wifi connect " + shq(net.ssid)];
        wifiAct.running = true;
    }

    function btAction(dev) {
        btAct.command = ["bluetoothctl", dev.connected ? "disconnect" : "connect", dev.mac];
        btAct.running = true;
    }

    function wifiGlyph(s) {
        if (s >= 80) return "󰤨";
        if (s >= 60) return "󰤟";
        if (s >= 40) return "󰤢";
        if (s >= 20) return "󰤜";
        return "󰤙";
    }

    // ── Grid ───────────────────────────────────────────────────────────────

    // Click-away for the drop-downs and sub-pages; sits under every card
    MouseArea {
        anchors.fill: parent
        z: 0
        visible: root.openMenu !== "" || root.subPage !== ""
        onClicked: {
            root.openMenu = "";
            root.subPage = "";
        }
    }

    // ── Tiles: absolutely positioned on the 7 × 8 grid ────────────────────

    // Wi-Fi — circle toggles the radio, body drops the network list
    Capsule {
        visible: root.hasTile("wifi")
        x: root.tx("wifi"); y: root.ty("wifi")
        width: root.tw("wifi"); height: root.th("wifi")
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        iconOn: "󰤨"
        iconOff: "󰖪"
        label: "Wi-Fi"
        sub: root.wifiOn ? (root.ssid !== "" ? root.ssid : "Connected") : "Off"
        checked: root.wifiOn
        onToggled: root.toggleWifi()
        onExpanded: root.toggleMenu("wifi")
    }

    // Focus — do not disturb; the whole tile toggles
    Capsule {
        visible: root.hasTile("focus")
        x: root.tx("focus"); y: root.ty("focus")
        width: root.tw("focus"); height: root.th("focus")
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        iconOn: "󰍷"
        iconOff: "󰍷"
        label: "Focus"
        sub: TogglesService.dnd ? "On" : "Off"
        checked: TogglesService.dnd
        onToggled: TogglesService.toggleDnd()
        onExpanded: TogglesService.toggleDnd()
    }

    // Bluetooth — circle toggles the radio, body drops the device list
    Capsule {
        visible: root.hasTile("bluetooth")
        x: root.tx("bluetooth"); y: root.ty("bluetooth")
        width: root.tw("bluetooth"); height: root.th("bluetooth")
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        iconOn: "󰂯"
        iconOff: "󰂲"
        label: "Bluetooth"
        sub: root.btOn
            ? (root.btCount > 0
                ? root.btCount + (root.btCount === 1 ? " device" : " devices")
                : "On")
            : "Off"
        checked: root.btOn
        onToggled: root.toggleBt()
        onExpanded: root.toggleMenu("bt")
    }

    // Game Mode — animations, blur and rounding off; whole tile toggles
    Capsule {
        visible: root.hasTile("gamemode")
        x: root.tx("gamemode"); y: root.ty("gamemode")
        width: root.tw("gamemode"); height: root.th("gamemode")
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        iconOn: "󰊗"
        iconOff: "󰊗"
        label: "Game Mode"
        sub: TogglesService.gameMode ? "On" : "Off"
        checked: TogglesService.gameMode
        onToggled: TogglesService.toggleGameMode()
        onExpanded: TogglesService.toggleGameMode()
    }

    // Night Light — round button; the circle keeps its shape at any tile
    // size (diameter = the tile's shorter span), hugging the right edge.
    RoundBtn {
        visible: root.hasTile("nightlight")
        readonly property real d: Math.min(root.tw("nightlight"), root.th("nightlight"))
        x: { var t = root.tile("nightlight"); return t ? root.cellX(t.x) + root.tw("nightlight") - d : 0; }
        y: root.ty("nightlight") + (root.th("nightlight") - d) / 2
        width: d
        height: d
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        glyph: "󰽧"
        checked: TogglesService.nightLight
        available: TogglesService.nightLightAvailable
        onClicked: TogglesService.toggleNightLight()
    }

    // Sound — full-width slider card
    SliderCard {
        id: volSlider
        visible: root.hasTile("sound")
        x: root.tx("sound"); y: root.ty("sound")
        width: root.tw("sound"); height: root.th("sound")
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        title: "Sound"
        icon: root.muted ? "󰝟" : "󰕾"
        onIconClicked: root.toggleMute()
        onExpanded: root.openSub("sound")
        onMoved: v => {
            value = v;
            root.pendingVol = v;
            volDebounce.restart();
        }
    }

    // Display — full-width slider card
    SliderCard {
        id: brightSlider
        visible: root.hasTile("display")
        x: root.tx("display"); y: root.ty("display")
        width: root.tw("display"); height: root.th("display")
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        title: "Display"
        icon: "󰃠"
        onExpanded: root.openSub("display")
        onMoved: v => {
            if (root.bMax > 0) {
                value = v;
                root.pendingBright = v;
                brightDebounce.restart();
            }
        }
    }

    // Now playing — full-width media bar along the bottom of the grid
    NowPlaying {
        visible: root.hasTile("nowplaying")
        x: root.tx("nowplaying")
        y: root.ty("nowplaying")
        width: root.tw("nowplaying")
        height: root.th("nowplaying")
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    // ── Notifications (7 × 2) ──
    NotifCard {
        visible: root.hasTile("notifications")
        x: root.tx("notifications")
        y: root.ty("notifications")
        width: root.tw("notifications")
        height: root.th("notifications")
        z: 1
        Behavior on x { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !TogglesService.gameMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        notifs: root.notifs
    }

    // ── Switch + page header (shared chrome for every sub-page) ───────────
    component Switch2: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()

        Layout.preferredWidth: 36
        Layout.preferredHeight: 21
        radius: height / 2
        color: checked ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.14)

        Rectangle {
            x: sw.checked ? parent.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 17
            height: 17
            radius: 9
            color: "#f2f2f2"
            Behavior on x { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    component PageHead: RowLayout {
        id: head
        property string title: ""
        signal back()

        Layout.fillWidth: true
        Layout.preferredHeight: 30
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.05)

            Text {
                anchors.centerIn: parent
                text: "‹"
                color: Qt.rgba(1, 1, 1, 0.65)
                font { pixelSize: 15; family: "SF Pro Text" }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: head.back()
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: head.title
            color: SettingsService.textPrimary
            font { pixelSize: 15; family: "SF Pro Text"; bold: true }
        }
    }

    // ── Sub-pages: full-width panels over the lower tile rows ─────────────
    Rectangle {
        id: sub
        x: root.cellX(0)
        // Bottom-anchored so it still fits when the panel is only as tall
        // as the rows in use; on a full-height panel it lands on row 2 as usual.
        y: root.height - 10 - height
        width: root.contentW
        height: Math.min(root.spanH(6), root.height - 20)
        radius: 16
        color: root.cardBg
        visible: root.subPage !== ""
        z: 20

        // ── Sound ──
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            visible: root.subPage === "sound"

            PageHead {
                title: "Sound"
                onBack: root.subPage = ""
            }

            Text {
                text: "Output"
                color: SettingsService.textMuted
                font { pixelSize: 10; family: "SF Pro Text" }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: SettingsService.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: root.muted ? "󰝟" : "󰕾"
                        color: "#0d0d0d"
                        font { pixelSize: 17; family: "JetBrainsMono Nerd Font" }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleMute()
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: root.sinkName !== "" ? root.sinkName : "Default output"
                        color: SettingsService.textPrimary
                        font { pixelSize: 12; family: "SF Pro Text"; bold: true }
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.muted ? "Muted" : "Volume"
                        color: SettingsService.textMuted
                        font { pixelSize: 10; family: "SF Pro Text" }
                    }
                }
            }

            // Big volume slider
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                Layout.maximumHeight: 22
                spacing: 10

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.07)
                    }

                    Rectangle {
                        width: parent.width * volSlider.value
                        height: parent.height
                        radius: height / 2
                        color: SettingsService.accentColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function setVol(mouse) {
                            var v = Math.max(0, Math.min(1, mouse.x / parent.width));
                            volSlider.value = v;
                            root.pendingVol = v;
                            volDebounce.restart();
                        }
                        onPressed: mouse => setVol(mouse)
                        onPositionChanged: mouse => { if (pressed) setVol(mouse) }
                    }
                }

                Text {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignVCenter
                    text: root.muted ? "Muted" : Math.round(volSlider.value * 100) + "%"
                    color: SettingsService.textMuted
                    font { pixelSize: 11; family: "SF Pro Text" }
                }
            }

            Item { Layout.fillHeight: true }   // keep content stacked at the top
        }

        // ── Display ──
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            visible: root.subPage === "display"

            PageHead {
                title: "Display"
                onBack: root.subPage = ""
            }

            Text {
                text: "Brightness"
                color: SettingsService.textMuted
                font { pixelSize: 10; family: "SF Pro Text" }
            }

            // Big brightness slider
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                Layout.maximumHeight: 22
                spacing: 10

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.07)
                    }

                    Rectangle {
                        width: parent.width * brightSlider.value
                        height: parent.height
                        radius: height / 2
                        color: SettingsService.accentColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function setBri(mouse) {
                            var v = Math.max(0, Math.min(1, mouse.x / parent.width));
                            if (root.bMax <= 0) return;
                            brightSlider.value = v;
                            root.pendingBright = v;
                            brightDebounce.restart();
                        }
                        onPressed: mouse => setBri(mouse)
                        onPositionChanged: mouse => { if (pressed) setBri(mouse) }
                    }
                }

                Text {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignVCenter
                    text: Math.round(brightSlider.value * 100) + "%"
                    color: SettingsService.textMuted
                    font { pixelSize: 11; family: "SF Pro Text" }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !TogglesService.nightLightAvailable
                horizontalAlignment: Text.AlignHCenter
                text: "Night Light needs hyprsunset — pacman -S hyprsunset"
                color: Qt.rgba(1, 1, 1, 0.45)
                font { pixelSize: 10; family: "SF Pro Text" }
            }

            // Night Light
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                spacing: 10
                visible: TogglesService.nightLightAvailable

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: TogglesService.nightLight
                        ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.07)

                    Text {
                        anchors.centerIn: parent
                        text: "󰽧"
                        color: TogglesService.nightLight ? "#0d0d0d" : SettingsService.textPrimary
                        font { pixelSize: 17; family: "JetBrainsMono Nerd Font" }
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: "Night Light"
                        color: SettingsService.textPrimary
                        font { pixelSize: 12; family: "SF Pro Text"; bold: true }
                    }

                    Text {
                        width: parent.width
                        text: TogglesService.temperature + " K"
                        color: SettingsService.textMuted
                        font { pixelSize: 10; family: "SF Pro Text" }
                    }
                }

                Switch2 {
                    Layout.alignment: Qt.AlignVCenter
                    checked: TogglesService.nightLight
                    onToggled: TogglesService.toggleNightLight()
                }
            }

            // Warmth slider — right is warmer
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Layout.maximumHeight: 20
                spacing: 10
                visible: TogglesService.nightLightAvailable

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.07)
                    }

                    Rectangle {
                        width: parent.width * (6500 - TogglesService.temperature) / 4000
                        height: parent.height
                        radius: height / 2
                        color: SettingsService.accentColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function setTemp(mouse) {
                            var f = Math.max(0, Math.min(1, mouse.x / parent.width));
                            root.pendingTemp = Math.round(6500 - f * 4000);
                            tempDebounce.restart();
                        }
                        onPressed: mouse => setTemp(mouse)
                        onPositionChanged: mouse => { if (pressed) setTemp(mouse) }
                    }
                }

                Text {
                    Layout.preferredWidth: 46
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignVCenter
                    text: TogglesService.temperature + " K"
                    color: SettingsService.textMuted
                    font { pixelSize: 11; family: "SF Pro Text" }
                }
            }

            Item { Layout.fillHeight: true }   // keep content stacked at the top
        }
    }

    // ── Drop-down: nearby networks / devices under their tile ─────────────
    Rectangle {
        id: menu
        x: root.openMenu === "bt" ? root.tx("bluetooth") : root.tx("wifi")
        y: root.openMenu === "bt" ? root.ty("bluetooth") : root.ty("wifi")
        width: root.openMenu === "bt" ? root.tw("bluetooth") : root.tw("wifi")
        height: Math.min(menuCol.implicitHeight + 12, root.height - y - 10)
        radius: 16
        color: root.cardBg
        border.width: 1
        border.color: root.hairline
        visible: root.openMenu !== ""
        z: 20

        readonly property bool isWifi: root.openMenu === "wifi"

        ColumnLayout {
            id: menuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 2

            // Header — the capsule it dropped from; chevron closes it
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                Rectangle {
                    x: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 18
                    color: SettingsService.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: menu.isWifi ? "󰤨" : "󰂯"
                        color: "#0d0d0d"
                        font { pixelSize: 17; family: "JetBrainsMono Nerd Font" }
                    }
                }

                Column {
                    x: 46
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 46 - 34
                    spacing: 1

                    Text {
                        width: parent.width
                        text: menu.isWifi ? "Wi-Fi" : "Bluetooth"
                        color: SettingsService.textPrimary
                        font { pixelSize: 12; family: "SF Pro Text"; bold: true }
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: menu.isWifi
                            ? (root.wifiOn ? (root.ssid !== "" ? root.ssid : "Connected") : "Off")
                            : (root.btOn ? (root.btCount > 0
                                ? root.btCount + " device" + (root.btCount > 1 ? "s" : "") : "On") : "Off")
                        color: SettingsService.textMuted
                        font { pixelSize: 10; family: "SF Pro Text" }
                        elide: Text.ElideRight
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⌃"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font { pixelSize: 12; family: "SF Pro Text" }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleMenu(menu.isWifi ? "wifi" : "bt")
                    }
                }
            }

            // Scanning indicator
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                spacing: 5
                visible: menu.isWifi ? root.wifiScanning : root.btScanning

                Rectangle {
                    width: 5
                    height: 5
                    radius: 3
                    color: SettingsService.accentColor
                }

                Text {
                    text: "Scanning"
                    color: SettingsService.textMuted
                    font { pixelSize: 9; family: "SF Pro Text" }
                }
            }

            // Radio off
            Text {
                Layout.fillWidth: true
                visible: menu.isWifi ? !root.wifiOn : !root.btOn
                horizontalAlignment: Text.AlignHCenter
                text: menu.isWifi ? "Wi-Fi is off" : "Bluetooth is off"
                color: Qt.rgba(1, 1, 1, 0.45)
                font { pixelSize: 10; family: "SF Pro Text" }
            }

            // Empty states — real rows so the menu always shows a body
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                visible: menu.isWifi && root.wifiOn && root.wifiNets.length === 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.wifiScanning ? "Looking for networks…" : "No networks found"
                color: Qt.rgba(1, 1, 1, 0.45)
                font { pixelSize: 10; family: "SF Pro Text" }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                visible: !menu.isWifi && root.btOn && root.btDevs.length === 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.btScanning ? "Looking for devices…" : "No devices found"
                color: Qt.rgba(1, 1, 1, 0.45)
                font { pixelSize: 10; family: "SF Pro Text" }
            }

            // Wi-Fi networks — tap to connect / disconnect
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, root.height - menu.y - 74)
                visible: menu.isWifi
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.wifiOn ? root.wifiNets : []

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 32
                    radius: 9
                    color: mHover.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.03)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 8

                        Text {
                            text: root.wifiGlyph(modelData.signal)
                            color: modelData.active ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.75)
                            font { pixelSize: 15; family: "JetBrainsMono Nerd Font" }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.ssid
                            color: modelData.active ? SettingsService.accentColor : SettingsService.textPrimary
                            font { pixelSize: 11; family: "SF Pro Text" }
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: modelData.secure
                            text: "󰌾"
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }
                        }

                        Text {
                            visible: modelData.active
                            text: "󰄬"
                            color: SettingsService.accentColor
                            font { pixelSize: 13; family: "JetBrainsMono Nerd Font" }
                        }
                    }

                    MouseArea {
                        id: mHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.wifiAction(modelData)
                    }
                }
            }

            // Bluetooth devices — tap to connect / disconnect
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, root.height - menu.y - 74)
                visible: !menu.isWifi
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.btOn ? root.btDevs : []

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 36
                    radius: 9
                    color: bHover.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.03)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: SettingsService.textPrimary
                            font { pixelSize: 11; family: "SF Pro Text" }
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 64
                            height: 20
                            radius: 10
                            color: modelData.connected ? Qt.rgba(1, 1, 1, 0.1) : SettingsService.accentColor

                            Text {
                                anchors.centerIn: parent
                                text: modelData.connected ? "Disconnect" : "Connect"
                                color: modelData.connected ? SettingsService.textPrimary : "#0d0d0d"
                                font { pixelSize: 9; family: "SF Pro Text" }
                            }
                        }
                    }

                    MouseArea {
                        id: bHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.btAction(modelData)
                    }
                }
            }
        }
    }

}
