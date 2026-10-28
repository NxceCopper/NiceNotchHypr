import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Settings app in its own FloatingWindow (see shell.qml), matched to the
// brief's layout: a search sidebar on the left, a hero card per section,
// and setting rows on the right. Only sections backed by real settings
// exist: Bar & Island, Appearance, and Control Center (with the drag &
// resize tile arranger).
Rectangle {
    id: root
    radius: 18              // notch corner radius minus the expanded-area inset
    clip: true
    color: SettingsService.bgBase

    property int page: 0            // 0 = Bar & Island, 1 = Appearance, 2 = Control Center
    property int envPage: -1        // optional QS_SETTINGS_PAGE override, read once
    property int focusAttempts: 0
    property string filter: ""

    signal dismissed()

    // ── Live state for the Control Center tab's tile preview ──
    // Mirrors the control centre's own reads so the arranger renders the
    // real tiles (SSID, device count, volume, brightness …) at preview size.
    property var notifs: null
    property bool wifiOn: false
    property string ssid: ""
    property bool btOn: false
    property int btCount: 0
    property bool muted: false
    property real volume: 0
    property real bright: 0

    readonly property bool ccLive: page === 2 && visible

    function refreshCC() {
        if (!ccWifi.running) ccWifi.running = true;
        if (!ccBt.running) ccBt.running = true;
        if (!ccVol.running) ccVol.running = true;
        if (!ccBright.running) ccBright.running = true;
    }
    onCcLiveChanged: if (ccLive) refreshCC()

    Timer {
        interval: 1500
        repeat: true
        running: root.ccLive
        onTriggered: root.refreshCC()
    }

    Process {
        id: ccWifi
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
        id: ccBt
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
        id: ccVol
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: line => {
                var m = line.match(/Volume:\s*([0-9.]+)/);
                if (m) {
                    root.muted = line.indexOf("[MUTED]") !== -1;
                    root.volume = Math.min(1, parseFloat(m[1]));
                }
            }
        }
    }

    Process {
        id: ccBright
        command: ["sh", "-c", 'd=$(basename $(ls -d /sys/class/backlight/* 2>/dev/null | head -1)); b=$(cat /sys/class/backlight/*/brightness 2>/dev/null); m=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null); echo "$d ${b:-0} ${m:-0}"']
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim().split(/\s+/);
                if (t.length >= 3 && t[0] !== "") {
                    var b = parseInt(t[1]);
                    var m = parseInt(t[2]);
                    if (m > 0) root.bright = Math.min(1, b / m);
                }
            }
        }
    }

    readonly property var sections: [
        { name: "Bar & Island",    tint: SettingsService.accentColor, letter: "B", glyph: "\uf108",
          desc: "Shape and size of the top bar and its expanded panels." },
        { name: "Appearance",      tint: SettingsService.accentColor, letter: "A", glyph: "\uf1fc",
          desc: "Accent colour and the base theme colours." },
        { name: "Control Center",  tint: SettingsService.accentColor, letter: "C", glyph: "\uf1de",
          desc: "Arrange, resize, add and remove the controls." }
    ]

    Component.onCompleted: {
        var p = Quickshell.env("QS_SETTINGS_PAGE");
        if (p === "appearance") envPage = 1;
        else if (p === "control") envPage = 2;
        else if (p === "island") envPage = 0;
    }

    // ── Esc closes the panel; focus is grabbed the moment it opens ──
    onVisibleChanged: {
        if (!visible) return
        page = envPage >= 0 ? envPage : 0
        filter = ""
        focusAttempts = 0
        Qt.callLater(function () { root.forceActiveFocus() })
        focusRetry.restart()
    }

    Keys.onEscapePressed: dismissed()

    Timer {
        id: focusRetry
        interval: 100
        repeat: true
        onTriggered: {
            if (!root.visible || root.activeFocus) { stop(); return }
            if (++root.focusAttempts > 8) { stop(); return }
            root.forceActiveFocus()
        }
    }

    // ── Layout ─────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // ── Sidebar ──
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 200
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.03)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // Search
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.09)

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⌕"
                        color: SettingsService.textMuted
                        font { pixelSize: 12; family: "SF Pro Text" }
                    }

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 6
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: SettingsService.textPrimary
                        font { pixelSize: 10; family: "SF Pro Text" }
                        onTextChanged: root.filter = text.toLowerCase()
                        Text {
                            visible: !searchInput.text && !searchInput.activeFocus
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search Settings"
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font { pixelSize: 10; family: "SF Pro Text" }
                        }
                    }
                }

                // Section list
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: {
                            var out = [];
                            for (var i = 0; i < root.sections.length; i++) {
                                if (root.filter === "" ||
                                    root.sections[i].name.toLowerCase().indexOf(root.filter) !== -1)
                                    out.push(i);
                            }
                            return out;
                        }

                        delegate: Rectangle {
                            required property int modelData
                            readonly property var sec: root.sections[modelData]
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: 8
                            color: root.page === modelData ? Qt.rgba(1, 1, 1, 0.13)
                                 : sideHover.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    radius: 9
                                    color: Qt.rgba(0, 0, 0, 0.35)
                                    border.width: 1
                                    border.color: Qt.colorEqual(sec.tint, SettingsService.accentColor)
                                        ? Qt.tint(sec.tint, Qt.rgba(1, 1, 1, 0.001)) : sec.tint

                                    Text {
                                        anchors.centerIn: parent
                                        text: sec.glyph
                                        color: sec.tint
                                        font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: sec.name
                                    color: root.page === modelData ? SettingsService.textPrimary
                                         : Qt.rgba(1, 1, 1, 0.65)
                                    font { pixelSize: 11; family: "SF Pro Text" }
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: sideHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.page = modelData
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // ── Main area ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // Hero card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.06)

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 26
                        height: 26
                        radius: 13
                        color: Qt.rgba(0, 0, 0, 0.3)
                        border.width: 1
                        border.color: root.sections[Math.max(0, Math.min(2, root.page))].tint

                        Text {
                            anchors.centerIn: parent
                            text: root.sections[Math.max(0, Math.min(2, root.page))].glyph
                            color: root.sections[Math.max(0, Math.min(2, root.page))].tint
                            font { pixelSize: 13; family: "JetBrainsMono Nerd Font" }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.sections[Math.max(0, Math.min(2, root.page))].name
                        color: SettingsService.textPrimary
                        font { pixelSize: 14; family: "SF Pro Text"; bold: true }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.sections[Math.max(0, Math.min(2, root.page))].desc
                        color: SettingsService.textMuted
                        font { pixelSize: 9; family: "SF Pro Text" }
                    }
                }
            }

            // ── Pages ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ══ Bar & Island ══
                Flickable {
                    anchors.fill: parent
                    clip: true
                    visible: root.page === 0
                    contentHeight: islandCol.implicitHeight + 4
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: islandCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 6

                        Text {
                            text: "Shape"
                            color: SettingsService.textMuted
                            font { pixelSize: 9; family: "SF Pro Text" }
                        }

                        // Island / Notch segmented
                        Rectangle {
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: 160
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.05)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 2

                                Repeater {
                                    model: ["Island", "Notch"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 6
                                        color: (modelData === "Island") === SettingsService.isIsland
                                            ? SettingsService.accentColor : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: (modelData === "Island") === SettingsService.isIsland
                                                ? "#0d0d0d" : Qt.rgba(1, 1, 1, 0.6)
                                            font { pixelSize: 10; family: "SF Pro Text"; bold: true }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: SettingsService.isIsland = modelData === "Island"
                                        }
                                    }
                                }
                            }
                        }

                        SetSlider {
                            label: "Notch width"; unit: " px"
                            from: 100; to: 320; val: SettingsService.notchWidth
                            onCommit: v => SettingsService.notchWidth = Math.round(v)
                        }

                        SetSlider {
                            label: "Notch height"; unit: " px"
                            from: 28; to: 60; val: SettingsService.notchHeight
                            onCommit: v => SettingsService.notchHeight = Math.round(v)
                        }

                        Text {
                            Layout.topMargin: 4
                            text: "Panel heights"
                            color: SettingsService.textMuted
                            font { pixelSize: 9; family: "SF Pro Text" }
                        }

                        SetSlider {
                            label: "Music"; unit: " px"
                            from: 160; to: 320; val: SettingsService.expandedHeightMusic
                            onCommit: v => SettingsService.expandedHeightMusic = Math.round(v)
                        }
                        SetSlider {
                            label: "Calendar"; unit: " px"
                            from: 300; to: 560; val: SettingsService.expandedHeightCalendar
                            onCommit: v => SettingsService.expandedHeightCalendar = Math.round(v)
                        }
                        SetSlider {
                            label: "Launcher"; unit: " px"
                            from: 340; to: 600; val: SettingsService.expandedHeightLauncher
                            onCommit: v => SettingsService.expandedHeightLauncher = Math.round(v)
                        }
                        SetSlider {
                            label: "Wallpaper"; unit: " px"
                            from: 180; to: 360; val: SettingsService.expandedHeightWallpaper
                            onCommit: v => SettingsService.expandedHeightWallpaper = Math.round(v)
                        }
                        SetSlider {
                            label: "Settings"; unit: " px"
                            from: 400; to: 640; val: SettingsService.expandedHeightSettings
                            onCommit: v => SettingsService.expandedHeightSettings = Math.round(v)
                        }
                        SetSlider {
                            label: "Control Center"; unit: " px"
                            from: 440; to: 680; val: SettingsService.expandedHeightControl
                            onCommit: v => SettingsService.expandedHeightControl = Math.round(v)
                        }
                    }
                }

                // ══ Appearance ══
                Flickable {
                    anchors.fill: parent
                    clip: true
                    visible: root.page === 1
                    contentHeight: lookCol.implicitHeight + 4
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: lookCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 6

                        Text {
                            text: "Accent"
                            color: SettingsService.textMuted
                            font { pixelSize: 9; family: "SF Pro Text" }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: ["#2ac3de", "#9fe8a0", "#4ade80", "#7aa2f7",
                                        "#bb9af7", "#f7768e", "#e0af68", "#e6e6e6"]
                                delegate: Rectangle {
                                    required property string modelData
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    radius: 11
                                    color: modelData
                                    border.width: String(SettingsService.accentColor) === modelData ? 2 : 0
                                    border.color: SettingsService.textPrimary

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: SettingsService.accentColor = modelData
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // "From wallpaper" — accent tracks the current
                            // wallpaper while on; off keeps manual picking.
                            Rectangle {
                                Layout.preferredWidth: autoLabel.implicitWidth + 16
                                Layout.preferredHeight: 22
                                radius: 11
                                color: SettingsService.accentFromWallpaper
                                    ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.07)

                                Text {
                                    id: autoLabel
                                    anchors.centerIn: parent
                                    text: "From wallpaper"
                                    color: SettingsService.accentFromWallpaper
                                        ? "#141418" : SettingsService.textPrimary
                                    font { pixelSize: 10; family: "SF Pro Text"; weight: Font.DemiBold }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        SettingsService.accentFromWallpaper = !SettingsService.accentFromWallpaper;
                                        if (SettingsService.accentFromWallpaper)
                                            WallpaperService.refreshAccent();
                                    }
                                }
                            }

                            HexField {
                                Layout.preferredWidth: 74
                                text: String(SettingsService.accentColor)
                                onAccepted: t => { if (isHex(t)) SettingsService.accentColor = t; }
                            }
                        }

                        Text {
                            Layout.topMargin: 6
                            text: "Base colours"
                            color: SettingsService.textMuted
                            font { pixelSize: 9; family: "SF Pro Text" }
                        }

                        Repeater {
                            model: [
                                { label: "Background",  prop: "bgBase" },
                                { label: "Surface",     prop: "bgSurface" },
                                { label: "Text",        prop: "textPrimary" },
                                { label: "Muted text",  prop: "textMuted" },
                                { label: "Border",      prop: "borderColor" }
                            ]
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24

                                Rectangle {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 14
                                    radius: 4
                                    color: SettingsService[modelData.prop]
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.2)
                                }

                                Text {
                                    Layout.preferredWidth: 84
                                    text: modelData.label
                                    color: SettingsService.textPrimary
                                    font { pixelSize: 10; family: "SF Pro Text" }
                                }

                                Item { Layout.fillWidth: true }

                                HexField {
                                    Layout.preferredWidth: 74
                                    text: String(SettingsService[modelData.prop])
                                    onAccepted: t => { if (isHex(t)) SettingsService[modelData.prop] = t; }
                                }
                            }
                        }

                        // ── Wallpaper (settings model ported from
                        //    dynamic-island-hyprland, MIT) ──
                        Text {
                            Layout.topMargin: 6
                            text: "Wallpaper"
                            color: SettingsService.textMuted
                            font { pixelSize: 9; family: "SF Pro Text" }
                        }

                        Text {
                            text: "Switch animation"
                            color: SettingsService.textPrimary
                            font { pixelSize: 10; family: "SF Pro Text" }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: ["grow", "wipe", "wave", "center", "outer",
                                        "fade", "any", "simple", "random"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 64
                                    height: 20
                                    radius: 10
                                    color: SettingsService.wallpaperTransitionType === modelData
                                        ? SettingsService.accentColor
                                        : Qt.rgba(1, 1, 1, 0.05)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: SettingsService.wallpaperTransitionType === modelData
                                            ? "#0d0d0d" : Qt.rgba(1, 1, 1, 0.6)
                                        font { pixelSize: 9; family: "SF Pro Text"; bold: true }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: SettingsService.wallpaperTransitionType = modelData
                                    }
                                }
                            }
                        }

                        SetToggle {
                            label: "Shell-drawn background"
                            val: SettingsService.enableQuickshellWallpaper
                            onToggled: v => SettingsService.enableQuickshellWallpaper = v
                        }

                        SetField {
                            label: "Library folder"
                            text: SettingsService.wallpaperLibraryPath
                            placeholder: "~/wallpaper, ~/Wallpaper (default)"
                            onAccepted: t => {
                                SettingsService.wallpaperLibraryPath = t.trim();
                                WallpaperService.rescan();
                            }
                            onReset: SettingsService.wallpaperLibraryPath = ""
                        }

                        SetField {
                            label: "Apply command"
                            text: SettingsService.wallpaperCustomCommand
                            placeholder: "awww + transition (default)"
                            onAccepted: t => SettingsService.wallpaperCustomCommand = t.trim()
                            onReset: SettingsService.wallpaperCustomCommand = ""
                        }
                    }
                }

                // ══ Control Center ══
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    visible: root.page === 2

                    // Layout header row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        spacing: 6

                        Text {
                            text: "Layout"
                            color: SettingsService.textMuted
                            font { pixelSize: 9; family: "SF Pro Text" }
                        }

                        Text {
                            text: "7 × 8"
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                        }

                        Item { Layout.fillWidth: true }

                        PillBtn { label: "Tidy";  onClicked: ed.tidy() }
                        PillBtn { label: "Undo";  enabled: ed.history.length > 0; onClicked: ed.undo() }
                        PillBtn { label: "Reset"; onClicked: ed.reset() }
                    }

                    // ── The arranger canvas ──
                    Rectangle {
                        id: ed
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        color: "transparent"
                        clip: true

                        // Working copy of the layout; committed to the service
                        property var tiles: []
                        property var history: []
                        property string selectedId: ""
                        property string dragId: ""
                        property string resizeId: ""
                        property real dragX: 0
                        property real dragY: 0
                        property int liveW: 0
                        property int liveH: 0
                        property real grabOffX: 0
                        property real grabOffY: 0

                        // Live rearrange preview while a tile is held: which
                        // tiles get pushed where, recomputed as the pointer moves.
                        readonly property var dispPlan: {
                            if (dragId === "") return null;
                            for (var i = 0; i < tiles.length; i++)
                                if (tiles[i].id === dragId)
                                    return displacePlan(tiles[i], alignTarget(tiles[i], dragX, dragY));
                            return null;
                        }
                        readonly property var dispMap: {
                            var m = {}, p = dispPlan;
                            if (p) for (var i = 0; i < p.moves.length; i++)
                                m[p.moves[i].id] = { x: p.moves[i].x, y: p.moves[i].y };
                            return m;
                        }

                        readonly property real pad: 6
                        readonly property real gap: 3
                        readonly property real stepX: (width - 2 * pad + gap) / 7
                        readonly property real stepY: (height - 2 * pad + gap) / 8
                        readonly property real cellW: stepX - gap
                        readonly property real cellH: stepY - gap

                        // Preview scale: keeps each tile's font-to-cell ratio
                        // identical to the live control centre (cellH from
                        // expandedHeightControl, gap 10, 20px panel padding).
                        readonly property real realCellH: (SettingsService.expandedHeightControl - 90) / 8
                        readonly property real pvs: cellH / realCellH

                        function reg(id) {
                            var r = root.registry;
                            for (var i = 0; i < r.length; i++) if (r[i].id === id) return r[i];
                            return null;
                        }
                        function cellX(x) { return pad + x * stepX }
                        function cellY(y) { return pad + y * stepY }
                        function spanW(w) { return w * stepX - gap }
                        function spanH(h) { return h * stepY - gap }

                        function pushHistory() {
                            history.push(JSON.stringify(tiles));
                            if (history.length > 30) history.shift();
                        }
                        function commit() {
                            SettingsService.controlLayout = JSON.parse(JSON.stringify(tiles));
                        }
                        function apply(mut) {
                            pushHistory();
                            mut();
                            commit();
                        }

                        function load() {
                            tiles = JSON.parse(JSON.stringify(SettingsService.controlLayout))
                                .filter(t => reg(t.id) !== null)
                                .map(t => {
                                    var r = reg(t.id);
                                    var w = Math.max(r.minW, Math.min(r.maxW, t.w));
                                    var h = Math.max(r.minH, Math.min(r.maxH, t.h));
                                    return { id: t.id, x: Math.min(7 - w, Math.max(0, t.x)),
                                                 y: Math.min(8 - h, Math.max(0, t.y)), w: w, h: h };
                                });
                            history = [];
                            selectedId = "";
                        }

                        function overlaps(a, b) {
                            return a.x < b.x + b.w && a.x + a.w > b.x &&
                                   a.y < b.y + b.h && a.y + a.h > b.y;
                        }
                        function fits(t, x, y, placed) {
                            var probe = { x: x, y: y, w: t.w, h: t.h };
                            for (var i = 0; i < placed.length; i++)
                                if (placed[i].id !== t.id && overlaps(probe, placed[i])) return false;
                            return true;
                        }
                        function firstFree(t, placed) {
                            for (var y = 0; y <= 8 - t.h; y++)
                                for (var x = 0; x <= 7 - t.w; x++)
                                    if (fits(t, x, y, placed)) return { x: x, y: y };
                            return null;
                        }
                        function overlapsOthers(id, x, y, w, h) {
                            var probe = { x: x, y: y, w: w, h: h };
                            for (var i = 0; i < tiles.length; i++) {
                                var o = tiles[i];
                                if (o.id !== id && overlaps(probe, o)) return true;
                            }
                            return false;
                        }
                        // Cell the pointer is over, clamped to the grid
                        function alignTarget(t, px, py) {
                            return {
                                x: Math.max(0, Math.min(7 - t.w, Math.round((px - pad) / stepX))),
                                y: Math.max(0, Math.min(8 - t.h, Math.round((py - pad) / stepY)))
                            };
                        }
                        // iOS-style rearrange: hovering an occupied cell pushes
                        // whatever sits there into the nearest free space.  The
                        // dragged tile's own old cell counts as free, so same
                        // sized neighbours simply swap.  Null when a pushed tile
                        // has nowhere to go — the drop is then blocked.
                        function displacePlan(t, target) {
                            var probe = { x: target.x, y: target.y, w: t.w, h: t.h };
                            var movers = [];
                            for (var i = 0; i < tiles.length; i++) {
                                var o = tiles[i];
                                if (o.id !== t.id && overlaps(probe, o)) movers.push(o);
                            }
                            var moves = [];
                            for (var m = 0; m < movers.length; m++) {
                                var o2 = movers[m];
                                var best = null, bd = Infinity;
                                for (var y = 0; y <= 8 - o2.h; y++) {
                                    for (var x = 0; x <= 7 - o2.w; x++) {
                                        var r = { x: x, y: y, w: o2.w, h: o2.h };
                                        if (overlaps(r, probe)) continue;   // must vacate the drop cell
                                        var ok = true;
                                        for (var j = 0; j < tiles.length && ok; j++) {
                                            var o3 = tiles[j];
                                            if (o3.id === o2.id || o3.id === t.id) continue;
                                            var vacated = false;           // tiles already pushed away
                                            for (var v = 0; v < moves.length; v++)
                                                if (moves[v].id === o3.id) { vacated = true; break; }
                                            if (vacated) continue;
                                            if (overlaps(r, o3)) ok = false;
                                        }
                                        for (var k = 0; k < moves.length && ok; k++)
                                            if (overlaps(r, moves[k])) ok = false;
                                        if (!ok) continue;
                                        var d = Math.abs(x - o2.x) + Math.abs(y - o2.y);
                                        if (d < bd) { bd = d; best = { id: o2.id, x: x, y: y, w: o2.w, h: o2.h }; }
                                    }
                                }
                                if (!best) return null;                  // pushed off the grid — no room
                                moves.push(best);
                            }
                            return { target: target, moves: moves };
                        }

                        function setTile(id, mut) {
                            apply(() => {
                                var next = [];
                                for (var i = 0; i < tiles.length; i++) {
                                    var t = JSON.parse(JSON.stringify(tiles[i]));
                                    if (t.id === id) mut(t);
                                    next.push(t);
                                }
                                tiles = next;
                            });
                        }

                        function commitDrag(t) {
                            var target = alignTarget(t, dragX, dragY);
                            var plan = displacePlan(t, target);
                            dragId = "";
                            if (!plan) { history.pop(); return; }          // nowhere to push — snap back
                            if (target.x === t.x && target.y === t.y && plan.moves.length === 0) {
                                history.pop(); return;
                            }
                            var next = [];
                            for (var i = 0; i < tiles.length; i++) {
                                var o = JSON.parse(JSON.stringify(tiles[i]));
                                if (o.id === t.id) { o.x = target.x; o.y = target.y; }
                                else {
                                    for (var j = 0; j < plan.moves.length; j++) {
                                        if (plan.moves[j].id === o.id) {
                                            o.x = plan.moves[j].x; o.y = plan.moves[j].y;
                                            break;
                                        }
                                    }
                                }
                                next.push(o);
                            }
                            tiles = next;   // history was pushed when the drag started
                            commit();
                        }

                        // Persist a corner resize. Must live on `ed`: swapping `tiles`
                        // destroys the delegate that owns the resize handler, so this
                        // has to be the last thing the handler calls.
                        function commitResize(t, w, h) {
                            if (w === t.w && h === t.h) return;
                            var next = [];
                            for (var i = 0; i < tiles.length; i++) {
                                var o = JSON.parse(JSON.stringify(tiles[i]));
                                if (o.id === t.id) { o.w = w; o.h = h; }
                                next.push(o);
                            }
                            tiles = next;
                            commit();
                        }

                        // ── Resize by dragging an edge or corner ──────────
                        function beginResize(t) {
                            selectedId = t.id;
                            resizeId = t.id;
                            liveW = t.w;
                            liveH = t.h;
                            pushHistory();
                        }
                        function dragResize(t, p, doW, doH) {
                            var r = reg(t.id);
                            var w = liveW, h = liveH;
                            if (doW) w = Math.max(r.minW, Math.min(r.maxW,
                                Math.min(7 - t.x, Math.round((p.x - cellX(t.x) + gap) / stepX))));
                            if (doH) h = Math.max(r.minH, Math.min(r.maxH,
                                Math.min(8 - t.y, Math.round((p.y - cellY(t.y) + gap) / stepY))));
                            // Never overlap: shrink to the largest size that fits
                            while (w > r.minW && overlapsOthers(t.id, t.x, t.y, w, h)) w--;
                            while (h > r.minH && overlapsOthers(t.id, t.x, t.y, w, h)) h--;
                            liveW = w;
                            liveH = h;
                        }
                        function endResize(t) {
                            var id = resizeId;
                            var w = liveW, h = liveH;
                            resizeId = "";
                            // LAST: committing swaps tiles and destroys the delegate
                            if (id === t.id) commitResize(t, w, h);
                        }

                        function tidy() {
                            apply(() => {
                                var placed = [];
                                var next = [];
                                for (var i = 0; i < tiles.length; i++) {
                                    var t = JSON.parse(JSON.stringify(tiles[i]));
                                    var spot = firstFree(t, placed);
                                    if (spot) { t.x = spot.x; t.y = spot.y; placed.push(t); }
                                    next.push(t);
                                }
                                tiles = next;
                            });
                        }
                        function undo() {
                            if (history.length === 0) return;
                            tiles = JSON.parse(history.pop());
                            commit();
                        }
                        function reset() {
                            apply(() => {
                                tiles = JSON.parse(JSON.stringify(SettingsService.defaultControlLayout));
                            });
                        }
                        function addTile(id) {
                            var r = reg(id);
                            if (!r) return;
                            var t = { id: id, x: 0, y: 0, w: r.defW, h: r.defH };
                            var spot = firstFree(t, tiles);
                            if (!spot) return;      // no room on the grid
                            t.x = spot.x; t.y = spot.y;
                            apply(() => { tiles = tiles.concat([t]); });
                            selectedId = id;
                        }
                        function removeTile(id) {
                            apply(() => { tiles = tiles.filter(t => t.id !== id); });
                            if (selectedId === id) selectedId = "";
                        }

                        Component.onCompleted: load()
                        Connections {
                            target: SettingsService
                            function onControlLayoutChanged() {
                                // Reload unless the change came from us
                                if (JSON.stringify(ed.tiles) !== JSON.stringify(SettingsService.controlLayout))
                                    ed.load();
                            }
                        }

                        // Click-away: clear selection
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: ed.selectedId = "";
                        }

                        // ── Tiles ──
                        Repeater {
                            model: ed.tiles

                            delegate: Rectangle {
                                id: tile
                                required property var modelData
                                readonly property var t: modelData
                                readonly property var meta: ed.reg(t.id)
                                readonly property bool selected: ed.selectedId === t.id
                                readonly property bool dragging: ed.dragId === t.id
                                readonly property bool dropBlocked: dragging && ed.dispPlan === null
                                // Live size while this tile is being corner-resized
                                readonly property int curW: ed.resizeId === t.id ? ed.liveW : t.w
                                readonly property int curH: ed.resizeId === t.id ? ed.liveH : t.h

                                x: dragging ? ed.dragX
                                    : (ed.dispMap[t.id] ? ed.cellX(ed.dispMap[t.id].x) : ed.cellX(t.x))
                                y: dragging ? ed.dragY
                                    : (ed.dispMap[t.id] ? ed.cellY(ed.dispMap[t.id].y) : ed.cellY(t.y))
                                Behavior on x {
                                    enabled: !dragging && !TogglesService.gameMode
                                    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                                }
                                Behavior on y {
                                    enabled: !dragging && !TogglesService.gameMode
                                    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                                }
                                width: ed.spanW(curW)
                                height: ed.spanH(curH)
                                // Morph: the tile eases into a new size instead of
                                // snapping — off while dragging or while this tile's
                                // own corner handle drives the size (that follows
                                // the pointer cell by cell).
                                Behavior on width {
                                    enabled: !dragging && ed.resizeId !== t.id && !TogglesService.gameMode
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                                Behavior on height {
                                    enabled: !dragging && ed.resizeId !== t.id && !TogglesService.gameMode
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                                color: "transparent"
                                opacity: dragging ? 0.55 : 1
                                z: dragging ? 10 : (selected ? 5 : 1)

                                // The real control, scaled to preview size.
                                // Sizes are pre-divided by pvs so `scale` lands
                                // them exactly on the cell — proportions stay
                                // identical to the live control centre.
                                readonly property real pvs: ed.pvs
                                readonly property bool tileOn: t.id === "wifi" ? root.wifiOn
                                    : t.id === "bluetooth" ? root.btOn
                                    : t.id === "focus" ? TogglesService.dnd
                                    : t.id === "gamemode" ? TogglesService.gameMode
                                    : t.id === "nightlight" ? TogglesService.nightLight
                                    : false

                                Capsule {
                                    visible: meta.kind === "capsule"
                                    width: tile.width / tile.pvs
                                    height: tile.height / tile.pvs
                                    scale: tile.pvs
                                    transformOrigin: Item.TopLeft
                                    iconOn: t.id === "wifi" ? "󰤨"
                                         : t.id === "bluetooth" ? "󰂯"
                                         : t.id === "gamemode" ? "󰊗" : "󰍷"
                                    iconOff: t.id === "wifi" ? "󰖪"
                                         : t.id === "bluetooth" ? "󰂲"
                                         : t.id === "gamemode" ? "󰊗" : "󰍷"
                                    label: meta.name
                                    sub: t.id === "wifi"
                                        ? (root.wifiOn ? (root.ssid !== "" ? root.ssid : "Connected") : "Off")
                                        : t.id === "bluetooth"
                                        ? (root.btOn ? (root.btCount > 0
                                            ? root.btCount + (root.btCount === 1 ? " device" : " devices")
                                            : "On") : "Off")
                                        : t.id === "focus"
                                        ? (TogglesService.dnd ? "On" : "Off")
                                        : (TogglesService.gameMode ? "On" : "Off")
                                    checked: tile.tileOn
                                }

                                // Night Light — square button, right-aligned
                                // in its cell like the live panel
                                RoundBtn {
                                    visible: meta.kind === "round"
                                    readonly property real d: Math.min(tile.width, tile.height) / tile.pvs
                                    x: tile.width - d * tile.pvs
                                    y: (tile.height - d * tile.pvs) / 2
                                    width: d
                                    height: d
                                    scale: tile.pvs
                                    transformOrigin: Item.TopLeft
                                    glyph: meta.glyph
                                    checked: tile.tileOn
                                    available: TogglesService.nightLightAvailable
                                }

                                SliderCard {
                                    visible: meta.kind === "slider"
                                    width: tile.width / tile.pvs
                                    height: tile.height / tile.pvs
                                    scale: tile.pvs
                                    transformOrigin: Item.TopLeft
                                    title: meta.name
                                    icon: t.id === "sound" ? (root.muted ? "󰝟" : "󰕾") : "󰃠"
                                    value: t.id === "sound" ? root.volume : root.bright
                                }

                                NowPlaying {
                                    visible: meta.kind === "media"
                                    width: tile.width / tile.pvs
                                    height: tile.height / tile.pvs
                                    scale: tile.pvs
                                    transformOrigin: Item.TopLeft
                                }

                                NotifCard {
                                    visible: meta.kind === "notif"
                                    width: tile.width / tile.pvs
                                    height: tile.height / tile.pvs
                                    scale: tile.pvs
                                    transformOrigin: Item.TopLeft
                                    notifs: root.notifs
                                }

                                // Selection / blocked outline, shaped like the
                                // control it wraps (pill, circle or card)
                                Rectangle {
                                    visible: selected || dropBlocked
                                    color: "transparent"
                                    border.width: 1.5
                                    border.color: dropBlocked ? "#f7768e"
                                                 : SettingsService.accentColor
                                    readonly property real rd: Math.min(tile.width, tile.height)
                                    x: meta.kind === "round" ? tile.width - rd : 0
                                    y: meta.kind === "round" ? (tile.height - rd) / 2 : 0
                                    width: meta.kind === "round" ? rd : tile.width
                                    height: meta.kind === "round" ? rd : tile.height
                                    radius: meta.kind === "capsule" || meta.kind === "round"
                                          ? Math.min(width, height) / 2 : 16 * tile.pvs
                                }

                                // Drag body — full tile; the corner resize handle is a
                                // later sibling, so it still wins at the corner.
                                MouseArea {
                                    id: bodyMa
                                    anchors.fill: parent
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor

                                    onPressed: mouse => {
                                        ed.selectedId = t.id;
                                        var p = bodyMa.mapToItem(ed, mouse.x, mouse.y);
                                        ed.grabOffX = p.x - tile.x;   // press point inside the tile
                                        ed.grabOffY = p.y - tile.y;
                                    }
                                    onPositionChanged: mouse => {
                                        if (!pressed) return;
                                        var p = bodyMa.mapToItem(ed, mouse.x, mouse.y);
                                        var dx = p.x - ed.grabOffX - tile.x;
                                        var dy = p.y - ed.grabOffY - tile.y;
                                        if (ed.dragId !== t.id) {
                                            if (Math.abs(dx) + Math.abs(dy) < 2) return;
                                            ed.dragId = t.id;
                                            ed.pushHistory();
                                        }
                                        // Absolute pointer math — the tile never jumps when grabbed
                                        ed.dragX = Math.max(0, Math.min(ed.width - tile.width,
                                            p.x - ed.grabOffX));
                                        ed.dragY = Math.max(0, Math.min(ed.height - tile.height,
                                            p.y - ed.grabOffY));
                                    }
                                    onReleased: {
                                        if (ed.dragId === t.id) ed.commitDrag(t);
                                    }
                                    onClicked: ed.selectedId = t.id
                                }

                                // ── Resize by dragging: right edge = width,
                                // bottom edge = height, corner = both ──
                                MouseArea {
                                    id: resizeRight
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 6
                                    preventStealing: true
                                    cursorShape: Qt.SizeHorCursor
                                    onPressed: ed.beginResize(t)
                                    onPositionChanged: mouse => {
                                        if (!pressed) return;
                                        ed.dragResize(t, resizeRight.mapToItem(ed, mouse.x, mouse.y), true, false);
                                    }
                                    onReleased: ed.endResize(t)
                                }

                                MouseArea {
                                    id: resizeBottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 6
                                    preventStealing: true
                                    cursorShape: Qt.SizeVerCursor
                                    onPressed: ed.beginResize(t)
                                    onPositionChanged: mouse => {
                                        if (!pressed) return;
                                        ed.dragResize(t, resizeBottom.mapToItem(ed, mouse.x, mouse.y), false, true);
                                    }
                                    onReleased: ed.endResize(t)
                                }

                                MouseArea {
                                    id: resizeCorner
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    width: 14
                                    height: 14
                                    preventStealing: true
                                    cursorShape: Qt.SizeDiagCursor
                                    onPressed: ed.beginResize(t)
                                    onPositionChanged: mouse => {
                                        if (!pressed) return;
                                        ed.dragResize(t, resizeCorner.mapToItem(ed, mouse.x, mouse.y), true, true);
                                    }
                                    onReleased: ed.endResize(t)
                                }

                                // Resize corner mark
                                Text {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: 3
                                    anchors.bottomMargin: 2
                                    text: "⌟"
                                    color: selected ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.25)
                                    font { pixelSize: 8; family: "SF Pro Text" }
                                    visible: selected
                                }

                                // Remove badge on the selected control's
                                // top-left, matching the reference
                                Rectangle {
                                    visible: selected && !dragging
                                    x: -9
                                    y: -9
                                    width: 18
                                    height: 18
                                    radius: 9
                                    z: 20
                                    color: "#f7768e"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: "#ffffff"
                                        font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ed.removeTile(t.id)
                                    }
                                }
                            }
                        }

                        // Empty-canvas hint
                        Text {
                            anchors.centerIn: parent
                            visible: ed.tiles.length === 0
                            text: "All controls removed — use Add a control below"
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font { pixelSize: 10; family: "SF Pro Text" }
                        }
                    }

                    // ── Add a control ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        spacing: 6

                        Text {
                            text: "Add a control"
                            color: SettingsService.textMuted
                            font { pixelSize: 9; family: "SF Pro Text" }
                        }

                        Repeater {
                            model: {
                                var on = {};
                                for (var i = 0; i < ed.tiles.length; i++) on[ed.tiles[i].id] = true;
                                var out = [];
                                for (var j = 0; j < root.registry.length; j++)
                                    if (!on[root.registry[j].id]) out.push(root.registry[j]);
                                return out;
                            }
                            delegate: Rectangle {
                                required property var modelData
                                Layout.preferredHeight: 20
                                Layout.preferredWidth: chipLabel.implicitWidth + 16
                                radius: 10
                                color: chipHover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)

                                Text {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    text: modelData.name + "  " + modelData.defW + "×" + modelData.defH
                                    color: Qt.rgba(1, 1, 1, 0.7)
                                    font { pixelSize: 9; family: "SF Pro Text" }
                                }

                                MouseArea {
                                    id: chipHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ed.addTile(modelData.id)
                                }
                            }
                        }

                        Text {
                            visible: {
                                var on = {};
                                for (var i = 0; i < ed.tiles.length; i++) on[ed.tiles[i].id] = true;
                                for (var j = 0; j < root.registry.length; j++)
                                    if (!on[root.registry[j].id]) return false;
                                return true;
                            }
                            text: "Every control is on the grid"
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font { pixelSize: 9; family: "SF Pro Text" }
                        }
                    }

                    // Hint
                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        verticalAlignment: Text.AlignVCenter
                        text: "Drag a control to move it, pull an edge or corner to resize."
                        color: Qt.rgba(1, 1, 1, 0.35)
                        font { pixelSize: 9; family: "SF Pro Text" }
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Control registry: names, glyph, supported and default sizes ──
    readonly property var registry: [
        { id: "wifi",          name: "Wi-Fi",          kind: "capsule", glyph: "󰤨", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 3, defH: 1 },
        { id: "focus",         name: "Focus",           kind: "capsule", glyph: "󰍷", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 4, defH: 1 },
        { id: "bluetooth",     name: "Bluetooth",       kind: "capsule", glyph: "󰂯", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 3, defH: 1 },
        { id: "gamemode",      name: "Game Mode",       kind: "capsule", glyph: "󰊗", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 3, defH: 1 },
        { id: "nightlight",    name: "Night Light",     kind: "round",   glyph: "󰽧", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 1, defH: 1 },
        { id: "sound",         name: "Sound",           kind: "slider",  glyph: "󰕾", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 7, defH: 1 },
        { id: "display",       name: "Display",         kind: "slider",  glyph: "󰃠", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 7, defH: 1 },
        { id: "notifications", name: "Notifications",   kind: "notif",   glyph: "", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 7, defH: 2 },
        { id: "nowplaying",    name: "Now Playing",     kind: "media",   glyph: "󰎈", minW: 1, maxW: 7, minH: 1, maxH: 8, defW: 7, defH: 2 }
    ]

    function isHex(t) { return /^#[0-9a-fA-F]{6}$/.test(t.trim()); }

    // ── Small parts ────────────────────────────────────────────────────────

    // Label + value + drag slider, committed on a short debounce
    component SetSlider: ColumnLayout {
        id: sl
        property string label: ""
        property string unit: ""
        property real from: 0
        property real to: 100
        property real val: 0
        signal commit(real v)

        Layout.fillWidth: true
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: sl.label
                color: SettingsService.textPrimary
                font { pixelSize: 10; family: "SF Pro Text" }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: Math.round(sl.val) + sl.unit
                color: SettingsService.textMuted
                font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
            }
        }

        Item {
            id: track
            Layout.fillWidth: true
            Layout.preferredHeight: 12

            readonly property real frac: sl.to > sl.from
                ? Math.max(0, Math.min(1, (sl.val - sl.from) / (sl.to - sl.from))) : 0

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 2.5
                radius: 1.5
                color: Qt.rgba(1, 1, 1, 0.12)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * track.frac
                height: 2.5
                radius: 1.5
                color: SettingsService.accentColor
            }
            Rectangle {
                x: parent.width * track.frac - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: SettingsService.accentColor
                border.width: 2
                border.color: SettingsService.bgBase
            }

            Timer { id: slDebounce; interval: 130; onTriggered: sl.commit(sl.val) }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function setFromMouse(mouse) {
                    var f = Math.max(0, Math.min(1, mouse.x / parent.width));
                    sl.val = sl.from + f * (sl.to - sl.from);
                    slDebounce.restart();
                }
                onPressed: mouse => setFromMouse(mouse)
                onPositionChanged: mouse => { if (pressed) setFromMouse(mouse) }
            }
        }
    }

    // Small rounded text button (Tidy / Undo / Reset)
    component PillBtn: Rectangle {
        id: pill
        property string label: ""
        property bool enabled: true
        signal clicked()

        Layout.preferredHeight: 20
        Layout.preferredWidth: labelTxt.implicitWidth + 16
        radius: 10
        opacity: enabled ? 1 : 0.4
        color: pillMouse.containsMouse && enabled ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)

        Text {
            id: labelTxt
            anchors.centerIn: parent
            text: pill.label
            color: Qt.rgba(1, 1, 1, 0.7)
            font { pixelSize: 9; family: "SF Pro Text" }
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (pill.enabled) pill.clicked()
        }
    }

    // Hex colour entry; commits on Enter / focus loss
    component HexField: Rectangle {
        id: hf
        property alias text: hexInput.text
        signal accepted(string t)

        Layout.preferredHeight: 20
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: hexInput.activeFocus ? 1 : 0
        border.color: SettingsService.accentColor

        TextInput {
            id: hexInput
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: SettingsService.textPrimary
            font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
            maximumLength: 7
            onEditingFinished: hf.accepted(text)
            Keys.onReturnPressed: { hf.accepted(text); event.accepted = true; }
        }
    }

    // Label + iOS-style switch row (settings app)
    component SetToggle: RowLayout {
        id: tg
        property string label: ""
        property bool val: false
        signal toggled(bool v)

        Layout.fillWidth: true
        Layout.preferredHeight: 24
        spacing: 8

        Text {
            text: tg.label
            color: SettingsService.textPrimary
            font { pixelSize: 10; family: "SF Pro Text" }
        }

        Item { Layout.fillWidth: true }

        Rectangle {
            Layout.preferredWidth: 30
            Layout.preferredHeight: 17
            radius: 9
            color: tg.val ? SettingsService.accentColor : Qt.rgba(1, 1, 1, 0.12)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: tg.val ? parent.width - width - 2 : 2
                width: 13
                height: 13
                radius: 6.5
                color: tg.val ? "#0d0d0d" : Qt.rgba(1, 1, 1, 0.75)
                Behavior on x {
                    NumberAnimation { duration: 140; easing.type: Easing.InOutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tg.toggled(!tg.val)
            }
        }
    }

    // Label + full-width text entry with a Default reset pill
    component SetField: ColumnLayout {
        id: sf
        property string label: ""
        property string text: ""
        property string placeholder: ""
        signal accepted(string t)
        signal reset()

        Layout.fillWidth: true
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: sf.label
                color: SettingsService.textPrimary
                font { pixelSize: 10; family: "SF Pro Text" }
            }

            Item { Layout.fillWidth: true }

            PillBtn {
                label: "Default"
                onClicked: sf.reset()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: fieldInput.activeFocus ? 1 : 0
            border.color: SettingsService.accentColor

            TextInput {
                id: fieldInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: SettingsService.textPrimary
                font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                // Follow the outer value; edited text wins while typing
                text: sf.text

                Connections {
                    target: sf
                    function onTextChanged() {
                        if (!fieldInput.activeFocus) fieldInput.text = sf.text;
                    }
                }

                onEditingFinished: sf.accepted(text)
                Keys.onReturnPressed: { sf.accepted(text); event.accepted = true; }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                visible: fieldInput.text === "" && !fieldInput.activeFocus
                text: sf.placeholder
                color: SettingsService.textMuted
                font { pixelSize: 10; family: "SF Pro Text" }
            }
        }
    }
}
