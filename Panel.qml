import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "wizwam.omaremote"
  ipcTarget: "wizwam.omaremote"
  manageIpc: false

  property string focusSection: "header"
  property bool cursorActive: false
  property int phraseIndex: 0
  property var revealed: ({})
  readonly property var activePhrases: [
    "Holding the door",
    "Waiting for a knock",
    "Keeping secrets folded",
    "Watching the wires"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool anyListening: remote.active
  readonly property color iconColor: anyListening ? foreground : dim
  readonly property color barIconColor: anyListening ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && remote.rustdesk.installed === true
  readonly property string toggleHint: remote.rustdeskActive ? "Stop RustDesk server" : "Start RustDesk server"
  readonly property bool showRustdesk: boolSetting("showRustdesk", true)
  readonly property bool showTeamviewer: boolSetting("showTeamviewer", true)
  readonly property bool showTailscaleSsh: boolSetting("showTailscaleSsh", true)
  readonly property bool showVnc: boolSetting("showVnc", true)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (value === true || value === "true") return true
    if (value === false || value === "false") return false
    return fallback
  }

  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var name in settings) if (name !== "id") entry[name] = settings[name]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function isRevealed(key) {
    return revealed && revealed[key] === true
  }

  function toggleReveal(key) {
    var next = {}
    for (var name in revealed) next[name] = revealed[name]
    next[key] = !isRevealed(key)
    revealed = next
  }

  function maskValue(value) {
    var text = String(value || "")
    var n = Math.min(14, Math.max(8, text.length))
    return "•".repeat(n)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      revealed = ({})
      remote.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      revealed = ({})
    }
  }

  Service {
    id: remote
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { remote.refresh(); return "ok" }
    function status(): string { return remote.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: remote.statusText && remote.statusText !== "Checking…" ? "Remote — " + remote.statusText : "Remote"
    iconComponent: Component {
      Item {
        RemoteIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          crossed: !root.anyListening
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) remote.toggleRustdesk()
      else if (buttonCode === Qt.MiddleButton) remote.copyToClipboard(remote.rustdesk.id, "RustDesk ID")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function() {
        if (!root.cursorActive) root.cursorActive = true
      }
      onActivateRequested: if (root.headerHasCursor) remote.toggleRustdesk()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.cursorActive = true; root.focusSection = "header" }

            PanelHero {
              id: hero
              width: parent.width
              title: "Remote"
              meta: remote.statusText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.anyListening ? 1.0 : 0.5
              iconComponent: Component {
                RemoteIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  crossed: !root.anyListening
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: remote.rustdesk.installed === true
                  checked: remote.rustdeskActive
                  busy: remote.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: remote.toggleRustdesk()
                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: remote.actionStatus !== "" || remote.lastError !== ""
            width: parent.width
            text: remote.actionStatus !== "" ? remote.actionStatus : remote.lastError
            color: remote.lastError !== "" && remote.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            text: "SHOW"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            ShowCheck { label: "RustDesk"; checked: root.showRustdesk; settingKey: "showRustdesk" }
            ShowCheck { label: "TeamViewer"; checked: root.showTeamviewer; settingKey: "showTeamviewer" }
            ShowCheck { label: "Tailscale SSH"; checked: root.showTailscaleSsh; settingKey: "showTailscaleSsh" }
            ShowCheck { label: "VNC / noVNC"; checked: root.showVnc; settingKey: "showVnc" }
          }

          Column {
            visible: root.showRustdesk
            width: parent.width
            spacing: Style.space(6)
            PanelSectionHeader { text: "RUSTDESK"; foreground: root.foreground; fontFamily: root.fontFamily }
            SecretRow {
              label: "RustDesk ID"
              value: remote.rustdesk.id
              emptyText: remote.rustdesk.installed ? "Open RustDesk once to mint an ID" : "Not installed"
              secretKey: "rustdeskId"
            }
            Text {
              width: parent.width
              leftPadding: Style.space(10)
              text: remote.rustdesk.statusText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            visible: root.showTeamviewer
            width: parent.width
            spacing: Style.space(6)
            PanelSectionHeader { text: "TEAMVIEWER"; foreground: root.foreground; fontFamily: root.fontFamily }
            SecretRow {
              label: "TeamViewer ID"
              value: remote.teamviewer.id
              emptyText: remote.teamviewer.installed ? "ID not readable yet" : "Not installed"
              secretKey: "teamviewerId"
            }
            Text {
              width: parent.width
              leftPadding: Style.space(10)
              text: remote.teamviewer.statusText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            visible: root.showTailscaleSsh
            width: parent.width
            spacing: Style.space(6)
            PanelSectionHeader { text: "TAILSCALE SSH"; foreground: root.foreground; fontFamily: root.fontFamily }
            SecretRow {
              label: "SSH login"
              value: remote.tailscaleSsh.login
              emptyText: "Not available"
              secretKey: "tsLogin"
            }
            SecretRow {
              label: "Tailscale IPv4"
              value: remote.tailscaleSsh.ip
              emptyText: "Not connected"
              secretKey: "tsIp"
            }
            SecretRow {
              label: "MagicDNS name"
              value: remote.tailscaleSsh.magicDns
              emptyText: "Not connected"
              secretKey: "tsDns"
            }
            SecretRow {
              label: "SSH command"
              value: remote.tailscaleSsh.command
              emptyText: "SSH is off"
              secretKey: "tsCmd"
            }
            Text {
              width: parent.width
              leftPadding: Style.space(10)
              text: remote.tailscaleSsh.statusText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            visible: root.showVnc
            width: parent.width
            spacing: Style.space(6)
            PanelSectionHeader { text: "VNC / NOVNC"; foreground: root.foreground; fontFamily: root.fontFamily }
            Text {
              visible: remote.vnc.length === 0
              width: parent.width
              leftPadding: Style.space(10)
              text: "No local VNC or noVNC listeners"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: remote.vnc
              SecretRow {
                required property var modelData
                required property int index
                label: String(modelData.name || "VNC session")
                value: String(modelData.url || modelData.address || "")
                emptyText: "No address"
                secretKey: "vnc-" + index
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.anyListening
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component ShowCheck: CursorSurface {
    id: check
    property string label: ""
    property bool checked: false
    property string settingKey: ""
    foreground: root.foreground
    implicitHeight: checkRow.implicitHeight + Style.spacing.rowPaddingX
    width: parent ? parent.width : 0

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.persistSetting(check.settingKey, !check.checked)
    }

    RowLayout {
      id: checkRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: check.checked ? "󰄲" : "󰄱"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }
      Text {
        text: check.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.fillWidth: true
      }
    }
  }

  component SecretRow: CursorSurface {
    id: secret
    property string label: ""
    property string value: ""
    property string emptyText: "Not available"
    property string secretKey: ""
    readonly property bool hasValue: String(value || "") !== ""
    readonly property bool shown: root.isRevealed(secretKey)
    readonly property string displayValue: secret.hasValue ? (secret.shown ? secret.value : root.maskValue(secret.value)) : secret.emptyText
    foreground: root.foreground
    implicitHeight: secretRow.implicitHeight + Style.spacing.rowPaddingX
    width: parent ? parent.width : 0

    RowLayout {
      id: secretRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(6)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          text: secret.label
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          Layout.fillWidth: true
        }
        Text {
          text: secret.displayValue
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      PanelActionButton {
        visible: secret.hasValue
        iconText: secret.shown ? "󰈉" : "󰈈"
        tooltipText: secret.shown ? "Hide" : "Show"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.toggleReveal(secret.secretKey)
      }
      PanelActionButton {
        visible: secret.hasValue
        iconText: "󰆏"
        tooltipText: "Copy to clipboard"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: remote.copyToClipboard(secret.value, secret.label)
      }
    }
  }
}
