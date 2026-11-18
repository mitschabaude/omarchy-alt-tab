import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "SwitcherModel.js" as Model

// GNOME-style Alt+Tab: while Alt is held, a panel on the main monitor shows
// a preview of every window, most recently used first, with one selected. Tab
// and Shift+Tab move the selection; letting go of Alt focuses that window and
// changes nothing else. Hyprland's bindings (bindings.lua) send
// the next, prev and commit shortcuts below.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // Window addresses, most recently focused first.
  property var recent: []

  // While open: the windows as they were when the switcher opened, the
  // selected one, and the screen it shows on.
  property bool open: false
  property var entries: []
  property int index: 0
  property var screen: null
  property var monitor: null
  // The monitor the panel always shows on, wherever the focused window is:
  // the "monitor" setting of this plugin's entry in shell.json. Empty, or not
  // connected, the panel shows on the monitor the user works on.
  property string panelMonitor: root.settings.monitor ? String(root.settings.monitor) : ""
  // The panel appears a moment after opening, so a quick Alt+Tab switches
  // without flashing it, as on GNOME.
  property bool shown: false
  // The window in front when the switcher opened, to give the keyboard back to
  // if nothing is picked: the panel held it, and Hyprland leaves it nowhere.
  property var previous: null
  // The panel's surface, up while the switcher is open.
  property bool mapped: false
  // The window to focus once the surface is gone, and its address while focus
  // settles on it.
  property var pending: null
  property string settling: ""

  // This plugin's entry in the plugins list of Omarchy's shell.json, e.g.
  // { "id": "alt-tab", "monitor": "DP-1" }.
  readonly property string pluginId: root.manifest && root.manifest.id ? String(root.manifest.id) : "alt-tab"
  property var settings: ({})

  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var entry = null
      try {
        var plugins = JSON.parse(text()).plugins
        if (Array.isArray(plugins)) {
          for (var i = 0; i < plugins.length; i++) {
            if (plugins[i] && plugins[i].id === root.pluginId) entry = plugins[i]
          }
        }
      } catch (error) {}
      root.settings = entry || ({})
    }
  }

  readonly property var selected: root.open && root.index < root.entries.length ? root.entries[root.index] : null

  function noteFocus(toplevel) {
    if (toplevel && toplevel.address) root.recent = Model.noteFocus(root.recent, String(toplevel.address))
  }

  // Whether Hyprland has reported the focused window since the shell started.
  // Until then, its focus history says which window is in front.
  property bool focusKnown: false

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      root.focusKnown = true
      var active = Hyprland.activeToplevel
      if (root.settling) {
        // Focus passing through other windows on the way is not use.
        if (active && String(active.address) === root.settling) {
          root.settling = ""
          settleTimeout.stop()
        }
        return
      }
      root.noteFocus(active)
    }

    // Hyprland gives a window the focus only once the surface holding the
    // keyboard is gone, and says when it is.
    function onRawEvent(event) {
      if (root.pending && String(event.name) === "closelayer" && String(event.data) === "alt-tab") root.focusPending()
    }
  }

  // Hyprland's focus history orders windows focused before the shell started.
  Component.onCompleted: {
    Hyprland.refreshToplevels()
    root.noteFocus(Hyprland.activeToplevel)
  }

  function windows() {
    var out = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      var wayland = toplevel.wayland
      // Dialogs come up with the window they belong to.
      if (!wayland || wayland.parent) continue
      var workspace = toplevel.workspace
      var ipc = toplevel.lastIpcObject || {}
      out.push({
        address: String(toplevel.address),
        toplevel: toplevel,
        appId: String(wayland.appId || ""),
        focusHistoryID: typeof ipc.focusHistoryID === "number" ? ipc.focusHistoryID : -1,
        minimized: !!workspace && String(workspace.name) === "special:minimized"
      })
    }
    return Model.order(out, root.recent)
  }

  function screenNamed(name) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return screens[i]
    }
    return null
  }

  function panelScreen(monitor) {
    var screen = root.screenNamed(root.panelMonitor) || (monitor ? root.screenNamed(monitor.name) : null)
    return screen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
  }

  function begin(direction) {
    var active = Hyprland.activeToplevel
    // Right after a switch, the pick counts as in front even before Hyprland
    // has given it the focus.
    var intended = root.settling
    if (root.pending) root.focusPending()
    if (!intended) root.noteFocus(active)
    var list = root.windows()
    if (list.length === 0) return
    root.entries = list
    var frontIsFocused = intended
      ? list[0].address === intended
      : root.focusKnown
        ? !!active && String(active.address) === list[0].address
        : list[0].focusHistoryID === 0
    root.index = Model.firstIndex(list.length, frontIsFocused, direction)
    root.previous = frontIsFocused ? list[0] : null
    // The monitor the user works on: the focused window's, or the one
    // Hyprland calls focused when no window is (which follows the pointer).
    // A minimized pick comes back there, and the panel shows there unless a
    // monitor is set.
    root.monitor = frontIsFocused && list[0].toplevel.monitor ? list[0].toplevel.monitor : Hyprland.focusedMonitor
    root.screen = root.panelScreen(root.monitor)
    root.shown = false
    root.settling = ""
    settleTimeout.stop()
    root.open = true
    root.mapped = true
    showDelay.restart()
  }

  function move(direction) {
    if (!root.open) root.begin(direction)
    else root.index = Model.step(root.index, root.entries.length, direction)
  }

  function next() { root.move(1) }
  function prev() { root.move(-1) }

  function select(index) {
    if (root.open && index >= 0 && index < root.entries.length) root.index = index
  }

  function stillOpen(window) {
    return !!window && Hyprland.toplevels.values.indexOf(window.toplevel) >= 0
  }

  function cancel() {
    if (root.open) root.finish(root.previous)
  }

  function commit() {
    if (!root.open) return
    // The pick may have closed while the switcher was open.
    root.finish(root.stillOpen(root.selected) ? root.selected : root.previous)
  }

  // Takes the panel down, then hands the focus to window (or leaves it). The
  // window under the pointer may get the focus in between; that is not
  // counted as use.
  function finish(window) {
    showDelay.stop()
    var previous = root.previous
    root.open = false
    root.shown = false
    root.previous = null
    root.mapped = false
    root.entries = []
    if (!root.stillOpen(window)) return
    // The pick is now the most recent window, and the one in front before
    // it the next.
    if (previous) root.recent = Model.noteFocus(root.recent, previous.address)
    root.recent = Model.noteFocus(root.recent, window.address)
    root.pending = window
    root.settling = window.address
    pendingTimeout.restart()
    settleTimeout.restart()
  }

  function focusPending() {
    var window = root.pending
    root.pending = null
    pendingTimeout.stop()
    if (root.stillOpen(window)) root.bringForward(window)
  }

  // In case Hyprland's word that the surface is gone never comes.
  Timer {
    id: pendingTimeout
    interval: 150
    onTriggered: root.focusPending()
  }

  // Stops ignoring focus changes if the pick never gets the focus.
  Timer {
    id: settleTimeout
    interval: 600
    onTriggered: root.settling = ""
  }

  Timer {
    id: showDelay
    interval: 150
    onTriggered: root.shown = root.open
  }

  // Focus the window and raise it, with
  // cursor warps off so the pointer stays put. Only the monitor showing the
  // window changes workspace. A minimized window first comes back to the
  // workspace in front of the user.
  function bringForward(window) {
    var address = window.address
    if (address.indexOf("0x") !== 0) address = "0x" + address
    var target = "window = \"address:" + address + "\""
    var steps = []
    var after = []
    if (window.minimized) {
      var monitor = root.monitor || Hyprland.focusedMonitor
      var workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
      if (!(workspace >= 1)) return
      steps.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", " + target + " })")
      steps.push("hl.dsp.window.move({ workspace = \"" + workspace + "\", " + target + " })")
      after.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"unset\", " + target + " })")
    }
    steps.push("hl.dsp.focus({ " + target + " })")
    steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
    Hyprland.dispatch("function() "
      + "local saved = { no_warps = hl.get_config(\"cursor.no_warps\"), "
      + "warp_on_change_workspace = hl.get_config(\"cursor.warp_on_change_workspace\") }; "
      + "hl.config({ cursor = { no_warps = true, warp_on_change_workspace = 0 } }); "
      + "pcall(function() " + steps.map(function(step) { return "hl.dispatch(" + step + ")" }).join("; ") + " end); "
      + "hl.config({ cursor = saved }) end")
    if (after.length > 0) {
      afterBringForward.steps = after
      afterBringForward.restart()
    }
  }

  Timer {
    id: afterBringForward
    property var steps: []
    interval: 400
    onTriggered: {
      for (var i = 0; i < steps.length; i++) Hyprland.dispatch(steps[i])
    }
  }

  GlobalShortcut {
    appid: "alt-tab"
    name: "next"
    description: "Open the window switcher, or select the next window"
    onPressed: root.next()
  }

  GlobalShortcut {
    appid: "alt-tab"
    name: "prev"
    description: "Open the window switcher, or select the previous window"
    onPressed: root.prev()
  }

  GlobalShortcut {
    appid: "alt-tab"
    name: "commit"
    description: "Focus the window selected in the switcher"
    onPressed: root.commit()
  }

  SwitcherWindow {
    switcher: root
  }
}
