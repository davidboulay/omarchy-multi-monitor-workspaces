import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Multi-Monitor Workspaces bar widget. Derived from Omarchy's
// omarchy.workspaces (MIT), which shows the global ids 1-10 on every screen.
//
// Paired with hypr/multi-monitor-workspaces.lua. Every screen owns a block of
// real ids (block B = B*10+1 .. B*10+10), remembered per screen in
// ~/.local/state/omarchy/multi-monitor-workspaces/blocks, which this widget
// reads. Screens are keyed exactly as the Lua side keys them: description,
// or description@connector when two identical panels describe themselves
// alike, or the connector when there is no description.
//
// Each bar shows only ITS screen's workspaces, labelled 1-9/0, and marks the
// one that screen is showing. A workspace adopted from an unplugged screen
// (see the adopted file) looks like any other; hover names where it came
// from. A workspace from another screen that hasn't been adopted yet shows
// briefly as a display glyph.
//
//   left-click    focus that workspace
//   right-click   send the focused window there
//   scroll        previous / next workspace on this screen
//
// The widget also projects its settings (count, extraKeys) into the plugin's
// state folder, where the Hyprland half reads them.
BarWidget {
  id: root
  moduleName: "io.github.davidboulay.multi-monitor-workspaces"

  readonly property int span: 10
  readonly property int count: Math.max(1, Math.min(root.span, Number(root.setting("count", 10)) || 10))
  readonly property bool extraKeys: root.setting("extraKeys", true) !== false
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/multi-monitor-workspaces"
  readonly property string parkedGlyph: "󰍹"

  property var blocksByKey: ({})
  property var keysByBlock: ({})
  property var adoptedFrom: ({})

  readonly property var monitor: {
    var win = QsWindow.window
    return win && win.screen ? Hyprland.monitorFor(win.screen) : null
  }

  function isMirror(m) {
    var ipc = m ? m.lastIpcObject : null
    return !!ipc && ((ipc.mirrorOf !== undefined && ipc.mirrorOf !== "none") || ipc.disabled === true)
  }

  function screenKey(m) {
    if (!m) return ""
    var desc = m.description || ""
    if (desc === "") return m.name
    var same = 0
    var values = Hyprland.monitors.values
    for (var i = 0; i < values.length; i++) {
      if (!root.isMirror(values[i]) && (values[i].description || "") === desc) same++
    }
    return same > 1 ? desc + "@" + m.name : desc
  }

  readonly property int block: {
    var key = root.screenKey(root.monitor)
    var b = root.blocksByKey[key]
    return b === undefined ? 0 : b
  }
  readonly property int base: root.block * root.span

  function parseBlocks(text) {
    var byKey = {}
    var byBlock = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var tab = lines[i].indexOf("\t")
      if (tab <= 0) continue
      var b = parseInt(lines[i].slice(0, tab), 10)
      var key = lines[i].slice(tab + 1)
      if (isNaN(b) || !key) continue
      byKey[key] = b
      byBlock[b] = key
    }
    root.blocksByKey = byKey
    root.keysByBlock = byBlock
  }

  FileView {
    id: blocksFile
    path: root.stateDir + "/blocks"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseBlocks(text())
    onLoadFailed: root.parseBlocks("")
  }

  function parseAdopted(text) {
    var map = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length < 3) continue
      var id = parseInt(parts[0], 10)
      if (!isNaN(id)) map[id] = parts.slice(2).join("\t")
    }
    root.adoptedFrom = map
  }

  FileView {
    id: adoptedFile
    path: root.stateDir + "/adopted"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseAdopted(text())
    onLoadFailed: root.parseAdopted("")
  }

  // The Hyprland half creates the blocks file on its first parse, which can
  // land after this widget loads; a watch on a missing file never fires.
  Timer {
    interval: 3000
    repeat: true
    running: Object.keys(root.blocksByKey).length === 0
    onTriggered: { blocksFile.reload(); adoptedFile.reload() }
  }

  // ── Settings projection ─────────────────────────────────────────────────
  readonly property string settingsText: "count=" + root.count + "\nextra_keys=" + (root.extraKeys ? 1 : 0) + "\n"

  FileView {
    id: settingsFile
    path: root.stateDir + "/settings"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.syncSettings()
    onLoadFailed: root.syncSettings()
  }

  Process {
    id: settingsWriter
    command: ["sh", "-c", "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/settings\"", "sh", root.stateDir, root.settingsText]
  }

  function syncSettings() {
    var current = ""
    try { current = settingsFile.text() } catch (e) { current = "" }
    if (current !== root.settingsText && !settingsWriter.running) settingsWriter.running = true
  }

  onSettingsTextChanged: syncSettings()

  // ── Workspaces on this screen ───────────────────────────────────────────
  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function onThisScreen(ws) {
    return !!ws && !!ws.monitor && !!root.monitor && ws.monitor.name === root.monitor.name
  }

  function isOwn(id) {
    return id > root.base && id <= root.base + root.span
  }

  function workspaceIds() {
    var ids = []
    for (var n = 1; n <= Math.min(5, root.count); n++) ids.push(root.base + n)

    var parked = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0 || !root.onThisScreen(values[i])) continue
      if (root.isOwn(id)) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (parked.indexOf(id) === -1) {
        parked.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    parked.sort(function(left, right) { return left - right })
    return ids.concat(parked)
  }

  function label(id) {
    if (root.isOwn(id)) {
      var digit = id - root.base
      return digit === root.span ? "0" : String(digit)
    }
    return root.parkedGlyph
  }

  function tooltip(id) {
    if (root.isOwn(id)) {
      var from = root.adoptedFrom[id]
      return from ? "From " + from + ", unplugged. Goes back when it returns." : ""
    }
    var owner = root.keysByBlock[Math.floor((id - 1) / root.span)]
    var digit = (id - 1) % root.span + 1
    var slot = digit === root.span ? "0" : String(digit)
    return owner
      ? "Workspace " + slot + " from " + owner + " (unplugged); goes back when it returns"
      : "Workspace " + id + " from another screen"
  }

  function dispatch(lua) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote(lua))
  }

  function focusWorkspace(id) {
    root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  function sendWindow(id) {
    root.dispatch("hl.dsp.window.move({ workspace = \"" + id + "\", follow = false })")
  }

  function stepWorkspace(delta) {
    var active = root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : root.base + 1
    var digit = root.isOwn(active) ? active - root.base : 1
    // Stops at the ends, like the SUPER + scroll keys: no wrap to slot 0.
    digit += delta
    if (digit < 1 || digit > root.count) return
    root.focusWorkspace(root.base + digit)
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        // This screen's visible workspace, not the globally focused one, so
        // each bar marks where its own monitor is.
        readonly property bool focused: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
        readonly property bool parked: !root.isOwn(modelData)

        bar: root.bar
        text: focused && !parked ? "󱓻" : root.label(modelData)
        tooltipText: root.tooltip(modelData)
        foreground: parked ? (root.bar ? root.bar.urgent : Color.urgent) : (root.bar ? root.bar.barForeground : Color.foreground)
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function(button) {
          if (button === Qt.RightButton) root.sendWindow(modelData)
          else if (button === Qt.LeftButton) root.focusWorkspace(modelData)
        }
        onWheelMoved: function(delta) { root.stepWorkspace(delta < 0 ? 1 : -1) }
      }
    }
  }
}
