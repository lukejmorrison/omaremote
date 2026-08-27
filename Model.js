function asObject(value) {
  return value && typeof value === "object" && typeof value.length !== "number" ? value : {}
}

function asList(value) {
  return value && typeof value.length === "number" ? value : []
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, lastError: "Empty status" }
  try {
    var data = JSON.parse(text)
    if (!data || data.ok === false) {
      return { ok: false, lastError: String((data && data.lastError) || "Status error") }
    }
    var rustdesk = asObject(data.rustdesk)
    var teamviewer = asObject(data.teamviewer)
    var ssh = asObject(data.tailscaleSsh)
    return {
      ok: true,
      listening: data.listening === true,
      rustdesk: {
        installed: rustdesk.installed === true,
        running: rustdesk.running === true,
        unitActive: rustdesk.unitActive === true,
        id: String(rustdesk.id || ""),
        statusText: String(rustdesk.statusText || "")
      },
      teamviewer: {
        installed: teamviewer.installed === true,
        running: teamviewer.running === true,
        id: String(teamviewer.id || ""),
        statusText: String(teamviewer.statusText || "")
      },
      tailscaleSsh: {
        installed: ssh.installed === true,
        enabled: ssh.enabled === true,
        online: ssh.online === true,
        user: String(ssh.user || ""),
        host: String(ssh.host || ""),
        ip: String(ssh.ip || ""),
        magicDns: String(ssh.magicDns || ""),
        login: String(ssh.login || ""),
        command: String(ssh.command || ""),
        statusText: String(ssh.statusText || "")
      },
      vnc: asList(data.vnc)
    }
  } catch (e) {
    return { ok: false, lastError: "Failed to parse remote status" }
  }
}

if (typeof module !== "undefined") {
  module.exports = { parseStatus: parseStatus }
}
