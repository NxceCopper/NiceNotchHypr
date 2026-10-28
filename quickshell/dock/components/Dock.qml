pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root

  required property var settings
  signal reorderRequested(int from, int to)
  signal pinRequested(string desktopId)
  signal unpinRequested(string desktopId)
  signal autoHideRequested(bool enabled)

  property int dragSource: -1
  property int dragTarget: -1
  property int openMenuCount: 0
  property bool autoHideRevealed: false
  // Shared hyprctl snapshot from the host shell; null disables auto-dodge.
  property var hyprlandData: null

  readonly property int iconSize: settings.iconSize || 52
  readonly property real magnification: settings.magnification || 1.65
  readonly property real magnificationRadius: settings.magnificationRadius || 110
  readonly property int edgeMargin: settings.margin === undefined ? 10 : settings.margin
  readonly property real backgroundOpacity: {
    var value = Number(settings.backgroundOpacity)
    return settings.backgroundOpacity === undefined || isNaN(value)
      ? 0.88
      : Math.max(0, Math.min(1, value))
  }
  readonly property bool reserveSpace: settings.reserveSpace === undefined ? true : settings.reserveSpace
  readonly property bool autoHide: settings.autoHide === undefined ? false : settings.autoHide
  // Auto-dodge: hide whenever a window overlaps the dock (instead of the
  // pointer-only auto-hide). The dock overlays windows while shown, so it
  // never reserves space while dodging is on.
  readonly property bool autoDodge: settings.autoDodge === true
  readonly property string clickAction: settings.clickAction || "focus-or-launch"
  readonly property string requestedPosition: settings.position || "bottom"
  readonly property string position: ["top", "bottom", "left", "right"].indexOf(requestedPosition) >= 0
    ? requestedPosition
    : "bottom"
  readonly property bool vertical: position === "left" || position === "right"
  readonly property bool fullLength: settings.fullLength === undefined ? false : settings.fullLength
  readonly property var pinned: settings.pinned || []
  readonly property int itemSize: iconSize + 14
  readonly property int reservedSize: iconSize + 24 + edgeMargin
  readonly property int mainPadding: 10
  readonly property int revealThickness: 3
  readonly property int crossExtent: vertical
    ? Math.ceil(iconSize * magnification + 80) + edgeMargin
    : Math.ceil(iconSize * magnification + 48) + edgeMargin
  readonly property bool keepAutoHideOpen: windowPointer.hovered
    || appPicker.visible || openMenuCount > 0 || dragSource >= 0
  readonly property bool dockShown: (!autoHide && !dodged) || autoHideRevealed
  // Auto-dodge: any mapped, unhidden window on this monitor's active
  // workspace whose rect intersects the dock background pushes the dock
  // off-screen. The reveal strip below still summons it (shared machinery
  // with auto-hide). Recomputes off HyprlandData, which Hyprland events
  // (open/close/move/workspace/fullscreen/...) keep fresh.
  readonly property bool dodged: {
    if (!autoDodge || !hyprlandData || !hyprlandData.ready)
      return false

    var mon = null
    const mons = hyprlandData.monitors || []
    for (var i = 0; i < mons.length; i++) {
      if (mons[i].name === root.screen.name) {
        mon = mons[i]
        break
      }
    }
    if (!mon || !mon.activeWorkspace)
      return false

    const left = mon.x + dockBackground.x
    const top = mon.y + dockBackground.y
    const right = left + dockBackground.width
    const bottom = top + dockBackground.height

    const wins = hyprlandData.windowList || []
    for (var j = 0; j < wins.length; j++) {
      const w = wins[j]
      if (!w || !w.mapped || w.hidden)
        continue
      if (w.monitor !== mon.id)
        continue
      if (!w.workspace || w.workspace.id !== mon.activeWorkspace.id)
        continue
      if (!w.at || !w.size || w.at.length < 2 || w.size.length < 2)
        continue
      if (w.at[0] < right && w.at[0] + w.size[0] > left
          && w.at[1] < bottom && w.at[1] + w.size[1] > top)
        return true
    }
    return false
  }
  readonly property real pointerPosition: !pointer.hovered
    ? -10000
    : vertical
      ? pointer.point.position.y - dockLayout.y
      : pointer.point.position.x - dockLayout.x

  function reorderOffset(index) {
    if (dragSource < dragTarget && index > dragSource && index <= dragTarget)
      return -itemSize
    if (dragSource > dragTarget && index >= dragTarget && index < dragSource)
      return itemSize
    return 0
  }

  function updateDragTarget(position) {
    dragTarget = Math.max(0, Math.min(pinned.length - 1, Math.floor(position / itemSize)))
  }

  function finishDrag() {
    var from = dragSource
    var to = dragTarget
    dragSource = -1
    dragTarget = -1
    if (from >= 0 && to >= 0 && from !== to)
      reorderRequested(from, to)
  }

  function updateAutoHideState() {
    if (!autoHide && !autoDodge) {
      hideTimer.stop()
      autoHideRevealed = false
    } else if (keepAutoHideOpen) {
      hideTimer.stop()
      autoHideRevealed = true
    } else if (autoHideRevealed) {
      hideTimer.restart()
    }
  }

  onAutoHideChanged: updateAutoHideState()
  onAutoDodgeChanged: updateAutoHideState()
  onDodgedChanged: {
    console.log("TDOCK dodged=" + dodged + " shown=" + dockShown)
    updateAutoHideState()
  }
  onKeepAutoHideOpenChanged: updateAutoHideState()

  anchors {
    top: position === "top" || (vertical && fullLength)
    bottom: position === "bottom" || (vertical && fullLength)
    left: position === "left" || (!vertical && fullLength)
    right: position === "right" || (!vertical && fullLength)
  }
  implicitWidth: vertical
    ? crossExtent
    : fullLength ? 0 : dockLayout.implicitWidth + mainPadding * 2
  implicitHeight: vertical
    ? fullLength ? 0 : dockLayout.implicitHeight + mainPadding * 2
    : crossExtent
  color: "transparent"
  exclusionMode: reserveSpace && !autoHide && !autoDodge ? ExclusionMode.Normal : ExclusionMode.Ignore
  WlrLayershell.exclusiveZone: reserveSpace && !autoHide && !autoDodge ? reservedSize : 0
  WlrLayershell.namespace: "hyprland-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {
    item: root.dockShown ? interactionArea : revealStrip
  }

  Timer {
    id: hideTimer

    interval: 800
    onTriggered: if (root.autoHide && !root.keepAutoHideOpen)
      root.autoHideRevealed = false
  }

  Item {
    id: interactionArea

    anchors.fill: parent
  }

  Item {
    id: revealStrip

    x: root.position === "right" ? parent.width - width : 0
    y: root.position === "bottom" ? parent.height - height : 0
    width: root.vertical ? root.revealThickness : parent.width
    height: root.vertical ? parent.height : root.revealThickness
  }

  Rectangle {
    id: dockBackground

    x: root.vertical
      ? root.position === "left" ? root.edgeMargin : parent.width - width - root.edgeMargin
      : 0
    y: root.vertical
      ? 0
      : root.position === "top" ? root.edgeMargin : parent.height - height - root.edgeMargin
    width: root.vertical ? root.iconSize + 24 : parent.width
    height: root.vertical ? parent.height : root.iconSize + 24
    radius: 20
    color: Qt.rgba(0.08, 0.09, 0.11, root.backgroundOpacity)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.18)
    transform: Translate {
      x: !root.autoHide || root.dockShown
        ? 0
        : root.position === "left"
          ? -(dockBackground.width + root.edgeMargin)
          : root.position === "right" ? dockBackground.width + root.edgeMargin : 0
      y: !root.autoHide || root.dockShown
        ? 0
        : root.position === "top"
          ? -(dockBackground.height + root.edgeMargin)
          : root.position === "bottom" ? dockBackground.height + root.edgeMargin : 0

      Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.28)
    }

    Grid {
      id: dockLayout

      // Offset the layout toward the screen edge so the icon itself, rather
      // than the icon-plus-indicator slot, is centered in the background.
      x: root.vertical
        ? root.position === "left" ? 6 : parent.width - implicitWidth - 6
        : (parent.width - implicitWidth) / 2
      y: root.vertical
        ? (parent.height - implicitHeight) / 2
        : root.position === "top" ? 6 : parent.height - implicitHeight - 6

      // Keep one spare cell so a settings reload cannot transiently reduce the
      // grid capacity before the repeater updates its delegates.
      columns: root.vertical ? 1 : Math.max(1, root.pinned.length + 1)
      rows: root.vertical ? Math.max(1, root.pinned.length + 1) : 1

      Repeater {
        model: root.pinned

        DockItem {
          required property string modelData
          required property int index

          desktopId: modelData
          itemIndex: index
          slotSize: root.itemSize
          iconSize: root.iconSize
          magnification: root.magnification
          magnificationRadius: root.magnificationRadius
          pointerPosition: root.pointerPosition
          clickAction: root.clickAction
          autoHide: root.autoHide
          position: root.position
          vertical: root.vertical
          reorderOffset: root.reorderOffset(index)
          onDragStarted: itemIndex => {
            root.dragSource = itemIndex
            root.dragTarget = itemIndex
          }
          onDragMoved: mainPosition => root.updateDragTarget(mainPosition)
          onDragFinished: root.finishDrag()
          onAddApplicationRequested: appPicker.open()
          onRemoveRequested: desktopId => root.unpinRequested(desktopId)
          onAutoHideToggled: enabled => root.autoHideRequested(enabled)
          onContextMenuVisibilityChanged: visible => {
            root.openMenuCount = Math.max(0, root.openMenuCount + (visible ? 1 : -1))
          }
        }
      }
    }

    HoverHandler {
      id: pointer
    }
  }

  DockAppPicker {
    id: appPicker

    anchorItem: dockBackground
    position: root.position
    pinned: root.pinned
    onApplicationSelected: desktopId => root.pinRequested(desktopId)
  }

  HoverHandler {
    id: windowPointer
  }
}
