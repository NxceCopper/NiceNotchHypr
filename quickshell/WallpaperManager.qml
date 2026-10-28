import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell

// Wallpaper carousel inside the expanded notch pill, matched to the brief's
// walkthrough card: a header ("Wallpaper" + the wallpaper's folder tag), a
// five-slot thumbnail strip with the selection centred at full size behind
// an accent border (neighbours 88%, edges 76% and dimmed), and a footer
// with the selected filename, the index/total and the Enter-to-apply hint.
// Arrow keys and the wheel move, Enter applies, right-click previews.
Item {
    id: root

    property string previewPath: ""
    property int currentIndex: 0
    property int focusAttempts: 0

    signal dismissed()

    readonly property var paths: WallpaperService.wallpapers
    readonly property int count: paths.length
    readonly property string selectedPath: count > 0 ? paths[wrap(currentIndex)] : ""
    readonly property string selectedName:
        selectedPath !== "" ? selectedPath.split("/").pop() : ""
    // Right-hand header tag: the folder the wallpaper lives in
    readonly property string selectedTag: {
        if (selectedPath === "") return "";
        var parts = selectedPath.split("/");
        return parts.length > 1 ? parts[parts.length - 2] : "";
    }

    function wrap(i) {
        if (count === 0) return -1;
        return ((i % count) + count) % count;
    }

    function indexOf(path) {
        const i = paths.indexOf(path);
        return i < 0 ? 0 : i;
    }

    function move(delta) {
        if (count > 0) currentIndex = wrap(currentIndex + delta);
    }

    function confirm() {
        if (selectedPath !== "") WallpaperService.setWallpaper(selectedPath);
    }

    // ── Open: reset, land on the current wallpaper, grab the keys ──
    onVisibleChanged: {
        if (!visible) return;
        previewPath = "";
        focusAttempts = 0;
        // Always rescan: freshly downloaded wallpapers appear instantly
        // (the service stages the new list and swaps it in without
        // flashing the strip empty).
        WallpaperService.rescan();
        currentIndex = indexOf(WallpaperService.currentWallpaper);
        Qt.callLater(function () { root.forceActiveFocus() });
        focusRetry.restart();
    }

    // A rescan-on-open swaps the list in after the index above was set;
    // re-anchor so the selection still sits on the current wallpaper.
    Connections {
        target: WallpaperService
        function onWallpapersChanged() {
            if (root.visible)
                root.currentIndex = root.indexOf(WallpaperService.currentWallpaper);
        }
    }

    Keys.onLeftPressed: event => { move(-1); event.accepted = true }
    Keys.onUpPressed: event => { move(-1); event.accepted = true }
    Keys.onRightPressed: event => { move(1); event.accepted = true }
    Keys.onDownPressed: event => { move(1); event.accepted = true }
    Keys.onReturnPressed: event => { confirm(); event.accepted = true }
    Keys.onEnterPressed: event => { confirm(); event.accepted = true }
    Keys.onEscapePressed: {
        if (previewPath !== "") previewPath = "";
        else dismissed();
    }

    Timer {
        id: focusRetry
        interval: 100
        repeat: true
        onTriggered: {
            if (!root.visible || root.activeFocus) {
                stop();
                return;
            }
            if (++root.focusAttempts > 8) {
                stop();
                return;
            }
            root.forceActiveFocus()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // ── Header: title left, folder tag right ──
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 8

            Text {
                text: "Wallpaper"
                color: SettingsService.textPrimary
                font { pixelSize: 15; family: "SF Pro Text"; bold: true }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.selectedTag
                color: SettingsService.textMuted
                font { pixelSize: 11; family: "SF Pro Text" }
                elide: Text.ElideRight
                Layout.maximumWidth: 260
            }
        }

        // ── Five-slot thumbnail strip ──
        Item {
            id: strip
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Slot geometry is fixed per slot (centre biggest); only the
            // pictures shift.  Widths come from the 16:9 thumbnail ratio —
            // the same centre-crop the desktop shows, so the corners you
            // see here are the corners you get — capped so the widest
            // layout fits the strip.
            readonly property var slotScale: [0.76, 0.88, 1, 0.88, 0.76]
            readonly property real slotGap: 10
            readonly property real thRatio: 16 / 9
            readonly property real maxCenterW: (width - 4 * slotGap) / 4.28
            readonly property real thH: Math.min(height, maxCenterW / thRatio)
            readonly property real thW: thH * thRatio

            function slotW(k) { return thW * slotScale[k]; }
            function slotH(k) { return thH * slotScale[k]; }
            function slotX(k) {
                var x = (width - (thW * 4.28 + 4 * slotGap)) / 2;
                for (var i = 0; i < k; i++) x += slotW(i) + slotGap;
                return x;
            }

            WheelHandler {
                acceptedModifiers: Qt.NoModifier
                onWheel: event => root.move(event.angleDelta.y > 0 ? -1 : 1)
            }

            Thumb {
                k: 0
                x: strip.slotX(0); z: 2
                anchors.verticalCenter: parent.verticalCenter
                width: strip.slotW(0); height: strip.slotH(0)
                path: root.count > 1 ? root.paths[root.wrap(root.currentIndex - 2)] : ""
                onClicked: root.move(-2)
            }

            Thumb {
                k: 1
                x: strip.slotX(1); z: 3
                anchors.verticalCenter: parent.verticalCenter
                width: strip.slotW(1); height: strip.slotH(1)
                path: root.count > 0 ? root.paths[root.wrap(root.currentIndex - 1)] : ""
                onClicked: root.move(-1)
            }

            Thumb {
                k: 2
                x: strip.slotX(2); z: 5
                anchors.verticalCenter: parent.verticalCenter
                width: strip.slotW(2); height: strip.slotH(2)
                path: root.selectedPath
                onClicked: root.confirm()
            }

            Thumb {
                k: 3
                x: strip.slotX(3); z: 3
                anchors.verticalCenter: parent.verticalCenter
                width: strip.slotW(3); height: strip.slotH(3)
                path: root.count > 0 ? root.paths[root.wrap(root.currentIndex + 1)] : ""
                onClicked: root.move(1)
            }

            Thumb {
                k: 4
                x: strip.slotX(4); z: 2
                anchors.verticalCenter: parent.verticalCenter
                width: strip.slotW(4); height: strip.slotH(4)
                path: root.count > 1 ? root.paths[root.wrap(root.currentIndex + 2)] : ""
                onClicked: root.move(2)
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                text: "󰋩  No wallpapers found"
                color: SettingsService.textMuted
                font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }
                visible: root.count === 0
            }
        }

        // ── Footer: filename left, index/total + apply hint right ──
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            spacing: 8

            Text {
                text: root.selectedName
                color: SettingsService.textMuted
                font { pixelSize: 12; family: "SF Pro Text" }
                elide: Text.ElideRight
                Layout.maximumWidth: 340
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.count > 0 ? (root.wrap(root.currentIndex) + "/" + root.count) : ""
                color: Qt.rgba(1, 1, 1, 0.35)
                font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
            }

            Text {
                text: "⏎ Enter to apply"
                color: SettingsService.textMuted
                font { pixelSize: 11; family: "SF Pro Text" }
            }
        }
    }

    // ── Preview overlay (right-click a thumb), rounded to match the pill ──
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 16
        color: Qt.rgba(0, 0, 0, 0.88)
        clip: true
        visible: root.previewPath !== ""

        MouseArea {
            anchors.fill: parent
            onClicked: root.previewPath = ""
        }

        Image {
            anchors.fill: parent
            anchors.margins: 10
            source: root.previewPath !== "" ? "file://" + root.previewPath : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }

    // One thumbnail slot: crossfades to its new picture when the selection
    // moves; the centre slot wears the accent border.
    component Thumb: Rectangle {
        id: th
        property int k: 2
        property string path: ""
        readonly property int dist: Math.abs(k - 2)
        signal clicked()

        property string shownPath: ""
        property string outPath: ""
        property real fadeP: 0

        radius: 12
        color: SettingsService.bgBase
        clip: true
        opacity: dist === 0 ? 1 : (dist === 1 ? 0.7 : 0.45)

        onPathChanged: {
            if (shownPath === "" || width < 4) {
                fadeAnim.stop();
                outPath = "";
                fadeP = 0;
                shownPath = path;
                return;
            }
            // Mid-fade (arrow key spam): keep the momentum, swap in the newest
            if (fadeAnim.running) {
                shownPath = path;
                return;
            }
            outPath = shownPath;
            shownPath = path;
            fadeP = 0;
            fadeAnim.start();
        }

        Component.onCompleted: {
            if (shownPath === "" && path !== "") shownPath = path;
        }

        NumberAnimation {
            id: fadeAnim
            target: th
            property: "fadeP"
            from: 0
            to: 1
            duration: 220
            easing.type: Easing.InOutCubic
            onFinished: th.outPath = ""
        }

        // Outgoing picture — fades away under the new one
        Image {
            visible: th.outPath !== "" && opacity > 0.01
            opacity: 1 - th.fadeP
            anchors.fill: parent
            source: th.outPath !== "" ? "file://" + WallpaperService.thumbFor(th.outPath) : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 480
            sourceSize.height: 270
            asynchronous: false
        }

        // Incoming picture — decoded synchronously so it is ready before
        // the fade starts; the card's own bgBase colour shows until then.
        // Uses the cached 640x360 thumbnail when the scan produced one.
        Image {
            anchors.fill: parent
            source: th.shownPath !== "" ? "file://" + WallpaperService.thumbFor(th.shownPath) : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 480
            sourceSize.height: 270
            asynchronous: false
        }

        // Rounded-corner curtains.  clip: true only clips children to the
        // bounding box, which left the picture corners square; a delegate-
        // local MultiEffect mask fixed it but crashed quickshell on config
        // reload (QQmlDelegateModel teardown).  These four slivers — the
        // corner square minus the arc, in the card's own colour — give the
        // same rounded look with plain shape nodes.
        Repeater {
            model: [
                [0, 0, 0],
                [1, 0, 90],
                [1, 1, 180],
                [0, 1, 270]
            ]
            delegate: Shape {
                x: modelData[0] * (th.width - th.radius)
                y: modelData[1] * (th.height - th.radius)
                width: th.radius
                height: th.radius
                rotation: modelData[2]

                ShapePath {
                    fillColor: SettingsService.bgBase
                    strokeColor: "transparent"
                    startX: 0
                    startY: 0
                    PathLine { x: th.radius; y: 0 }
                    PathArc {
                        x: 0
                        y: th.radius
                        radiusX: th.radius
                        radiusY: th.radius
                        direction: PathArc.Counterclockwise
                    }
                    PathLine { x: 0; y: 0 }
                }
            }
        }

        // Selection ring — an overlay, because a Rectangle's own border
        // paints underneath its children and the pictures would cover it.
        Rectangle {
            anchors.fill: parent
            radius: th.radius
            color: "transparent"
            border.width: th.dist === 0 ? 2 : 1
            border.color: th.dist === 0
                ? SettingsService.accentColor
                : (thHover.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
        }

        MouseArea {
            id: thHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    root.previewPath = th.path;
                } else {
                    th.clicked();
                }
            }
        }
    }
}
