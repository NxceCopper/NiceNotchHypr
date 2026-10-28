pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "components"

Item {
  id: root

  required property string configPath

  // Shared hyprctl snapshot from the host shell (window list + monitors +
  // active workspaces); powers auto-dodge. Null when running standalone,
  // which disables dodge.
  property var hyprlandData: null

  property var settings: ({
    iconSize: 42,
    magnification: 1.2,
    magnificationRadius: 95,
    margin: 10,
    backgroundOpacity: 0.88,
    position: "bottom",
    fullLength: false,
    reserveSpace: true,
    autoHide: false,
    clickAction: "focus-or-launch",
    pinned: [
      "org.gnome.Nautilus",
      "com.mitchellh.ghostty",
      "com.google.Chrome",
      "code",
      "obsidian",
      "chatgpt"
    ]
  })

  function loadSettings(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (!parsed.pinned || !Array.isArray(parsed.pinned))
        throw new Error("'pinned' must be an array")
      settings = parsed
    } catch (error) {
      console.warn("Dock: could not load " + configPath + ":", error)
    }
  }

  function reorderPinned(from, to) {
    if (from === to || from < 0 || to < 0
        || from >= settings.pinned.length || to >= settings.pinned.length)
      return

    var pinned = settings.pinned.slice()
    var moved = pinned.splice(from, 1)[0]
    pinned.splice(to, 0, moved)

    savePinned(pinned)
  }

  function pinApplication(desktopId) {
    if (!desktopId || settings.pinned.indexOf(desktopId) >= 0) return

    var pinned = settings.pinned.slice()
    pinned.push(desktopId)
    savePinned(pinned)
  }

  function unpinApplication(desktopId) {
    var index = settings.pinned.indexOf(desktopId)
    if (index < 0) return

    var pinned = settings.pinned.slice()
    pinned.splice(index, 1)
    savePinned(pinned)
  }

  function savePinned(pinned) {
    saveSetting("pinned", pinned)
  }

  function saveSetting(key, value) {
    var updated = {}
    for (var setting in settings)
      updated[setting] = settings[setting]
    updated[key] = value

    settings = updated
    configFile.setText(JSON.stringify(updated, null, 2) + "\n")
  }

  FileView {
    id: configFile

    path: root.configPath
    watchChanges: true
    printErrors: false
    blockWrites: true
    onLoaded: root.loadSettings(text())
    // FileView.text() is still stale inside onFileChanged. Reload first and
    // parse the fresh contents when onLoaded fires.
    onFileChanged: reload()
    onSaveFailed: error => console.warn("Dock: could not save " + root.configPath + ":", error)
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      Dock {
        required property var modelData
        screen: modelData
        settings: root.settings
        hyprlandData: root.hyprlandData
        onReorderRequested: (from, to) => root.reorderPinned(from, to)
        onPinRequested: desktopId => root.pinApplication(desktopId)
        onUnpinRequested: desktopId => root.unpinApplication(desktopId)
        onAutoHideRequested: enabled => root.saveSetting("autoHide", enabled)
      }
    }
  }
}
