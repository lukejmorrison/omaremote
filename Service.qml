import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  // Injected only when this file is loaded as the plugin `service` entry.
  property var shell: null
  property var pluginRegistry: null

  property bool listening: false
  property var rustdesk: ({ installed: false, running: false, unitActive: false, id: "", statusText: "Checking…" })
  property var teamviewer: ({ installed: false, running: false, id: "", statusText: "Checking…" })
  property var tailscaleSsh: ({ installed: false, enabled: false, online: false, user: "", host: "", ip: "", magicDns: "", login: "", command: "", statusText: "Checking…" })
  property var vnc: []

  property int _desired: -1
  readonly property bool rustdeskActive: _desired === -1 ? rustdesk.running === true : (_desired === 1)
  readonly property bool active: listening || rustdeskActive
  property bool refreshing: false
  property string statusText: "Checking…"
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 3600)
  readonly property bool busy: statusProcess.running || controlProcess.running
  readonly property string helperPath: resolvedHelper()

  property string _statusOutput: ""
  property string _statusError: ""
  property string _controlOutput: ""
  property string _controlError: ""

  function resolvedHelper() {
    var url = String(Qt.resolvedUrl("./status.py"))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return url
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (statusProcess.running || helperPath === "") return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["python3", helperPath]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read remote status"
      return
    }
    rustdesk = parsed.rustdesk
    teamviewer = parsed.teamviewer
    tailscaleSsh = parsed.tailscaleSsh
    vnc = parsed.vnc
    listening = parsed.listening === true
    if (_desired !== -1 && rustdesk.running === (_desired === 1)) _desired = -1

    var parts = []
    if (rustdesk.running) parts.push("RustDesk")
    if (teamviewer.running) parts.push("TeamViewer")
    if (tailscaleSsh.enabled) parts.push("SSH")
    if (vnc.length > 0) parts.push("VNC")
    statusText = parts.length > 0 ? parts.join(" · ") : "Nothing listening"
    lastError = ""
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    actionStatus = "Copied " + (label || "value")
    actionStatusTimer.restart()
  }

  function openApp(command) {
    if (!command || command.length === 0) return
    Quickshell.execDetached(["uwsm-app", "--"].concat(command))
  }

  function openUrl(url) {
    var text = String(url || "")
    if (text === "") return
    Quickshell.execDetached(["omarchy-launch-browser", text])
  }

  function startRustdesk() {
    runControl(["systemctl", "--user", "start", "rustdesk.service"], 1)
  }

  function stopRustdesk() {
    runControl(["systemctl", "--user", "stop", "rustdesk.service"], 0)
  }

  function toggleRustdesk() {
    if (rustdeskActive) stopRustdesk()
    else startRustdesk()
  }

  function runControl(command, desired) {
    if (controlProcess.running) return
    _desired = desired
    _controlOutput = ""
    _controlError = ""
    controlProcess.command = command
    controlProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.shell === null
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: root.shell === null
    onTriggered: {
      ticks += 1
      if (root.listening || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1200
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 4) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = root.elideStatus(stderr || stdout || "Could not read remote status")
    }
  }

  property var _hoverTarget: null

  readonly property var barIconNames: ({
    "omarchy.menu": "Omarchy menu",
    "omarchy.workspaces": "Workspaces",
    "omarchy.clock": "Clock",
    "omarchy.media": "Media",
    "omarchy.indicators": "Indicators",
    "omarchy.system-update": "Omarchy updates",
    "omarchy.tray": "System tray",
    "omarchy.weather": "Weather",
    "omarchy.microphone": "Microphone",
    "omarchy.audio": "Audio",
    "omarchy.network": "Network",
    "omarchy.tailscale": "Tailscale",
    "omarchy.agents": "Agents",
    "omarchy.power": "Power",
    "omarchy.bluetooth": "Bluetooth",
    "omarchy.monitor": "Display",
    "omarchy.keyboard-layout": "Keyboard layout",
    "omarchy.active-window": "Active window",
    "omarchy.dropbox": "Dropbox",
    "wizwam.omaremote": "OmaRemote",
    "wizwam.remote": "OmaRemote",
    "wizwam.rustdesk": "OmaRemote"
  })

  function barIconLabel(id) {
    var key = String(id || "")
    if (barIconNames[key]) return barIconNames[key]
    var plugins = pluginRegistry && pluginRegistry.installedPlugins
    var manifest = plugins ? plugins[key] : null
    if (manifest && manifest.name) return String(manifest.name)
    return key.replace(/^omarchy\./, "").replace(/^wizwam\./, "").replace(/[-.]/g, " ")
  }

  function moduleNameOf(item) {
    var cur = item
    for (var i = 0; i < 12 && cur; i++) {
      try {
        if (cur.moduleName) return String(cur.moduleName)
      } catch (e) {}
      try { cur = cur.parent } catch (e2) { return "" }
    }
    return ""
  }

  function barButtons(bar) {
    var found = []
    if (!bar || !bar.clickTargets) return found
    for (var i = 0; i < bar.clickTargets.length; i++) {
      if (bar.clickTargets[i]) found.push(bar.clickTargets[i])
    }
    return found
  }

  function applyBarIconTooltips() {
    var bar = shell && shell.bar
    if (!bar) return
    var buttons = barButtons(bar)
    for (var i = 0; i < buttons.length; i++) {
      var item = buttons[i]
      var current = ""
      try { current = String(item.tooltipText || "") } catch (e) {}
      if (current !== "") continue
      var name = moduleNameOf(item)
      if (!name) continue
      try { item.tooltipText = barIconLabel(name) } catch (e2) {}
    }
  }

  // First-party icons leave tooltipText blank and only call showTooltip on
  // mouse-enter. Filling the property later is not enough unless we also
  // fire showTooltip ourselves when the pointer is already over the icon.
  function pollBarIconHover() {
    var bar = shell && shell.bar
    if (!bar || typeof bar.showTooltip !== "function") return
    var buttons = barButtons(bar)
    var hovered = null
    var text = ""
    for (var i = 0; i < buttons.length; i++) {
      var item = buttons[i]
      var isHovered = false
      try { isHovered = item.tooltipHovered === true } catch (e) {}
      if (!isHovered) continue
      hovered = item
      try { text = String(item.tooltipText || "") } catch (e2) {}
      if (text === "") {
        var name = moduleNameOf(item)
        text = barIconLabel(name)
        try { if (text) item.tooltipText = text } catch (e3) {}
      }
      break
    }
    if (hovered === root._hoverTarget) return
    if (root._hoverTarget && typeof bar.hideTooltip === "function") {
      try { bar.hideTooltip(root._hoverTarget) } catch (e4) {}
    }
    root._hoverTarget = hovered
    if (hovered && text) bar.showTooltip(hovered, text)
  }

  Timer {
    id: barIconTimer
    interval: 1200
    running: root.shell !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: root.applyBarIconTooltips()
  }

  Timer {
    id: barHoverTimer
    interval: 80
    running: root.shell !== null
    repeat: true
    onTriggered: root.pollBarIconHover()
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector { id: controlStdout; waitForEnd: true; onStreamFinished: root._controlOutput = text }
    stderr: StdioCollector { id: controlStderr; waitForEnd: true; onStreamFinished: root._controlError = text }
    onExited: function(exitCode) {
      var stdout = String(controlStdout.text || root._controlOutput || "")
      var stderr = String(controlStderr.text || root._controlError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(stderr || stdout || "Command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
        settleTimer.ticks = 0
        settleTimer.running = true
      }
      delayedRefresh.restart()
    }
  }
}
