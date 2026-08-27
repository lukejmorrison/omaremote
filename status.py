#!/usr/bin/env python3
"""Remote-access status for the Omarchy bar plugin. Prints one JSON object."""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
from pathlib import Path

TV_ID_RE = re.compile(
  r"(?:UpdateMachineID:\s*New machineID\s*=\s*|ClientId:|ClientID\s*=\s*)(\d{6,12})"
)
SS_PORT_RE = re.compile(r":(\d+)\s")


def run(command, timeout=3):
  try:
    completed = subprocess.run(
      command,
      check=False,
      capture_output=True,
      text=True,
      timeout=timeout,
    )
  except (OSError, subprocess.TimeoutExpired):
    return 1, ""
  return completed.returncode, (completed.stdout or "").strip()


def first_line(text):
  for line in str(text or "").splitlines():
    value = line.strip()
    if value:
      return value
  return ""


def unit_active(name, user=True):
  cmd = ["systemctl", "--user", "is-active", name] if user else ["systemctl", "is-active", name]
  _, out = run(cmd, timeout=2)
  return out == "active"


def rustdesk_status():
  binary = shutil.which("rustdesk")
  installed = binary is not None
  unit = unit_active("rustdesk.service")
  pgrep_code, _ = run(["pgrep", "-x", "rustdesk"], timeout=2)
  process = pgrep_code == 0
  running = unit or process
  rd_id = ""
  if installed:
    code, out = run([binary, "--get-id"], timeout=2)
    candidate = first_line(out)
    if code == 0 and candidate.isdigit():
      rd_id = candidate
  if not installed:
    status = "Not installed"
  elif unit:
    status = "Listening"
  elif process:
    status = "App running"
  else:
    status = "Stopped"
  return {
    "installed": installed,
    "running": running,
    "unitActive": unit,
    "id": rd_id,
    "statusText": status,
  }


def teamviewer_id_from_logs():
  paths = [
    Path.home() / ".local/share/teamviewer15/logfiles/TeamViewer15_Logfile.log",
    Path("/var/log/teamviewer15/TeamViewer15_Logfile.log"),
  ]
  for path in paths:
    try:
      data = path.read_text(encoding="utf-8", errors="replace")[-400000:]
    except OSError:
      continue
    matches = TV_ID_RE.findall(data)
    if matches:
      return matches[-1]
  return ""


def teamviewer_status():
  binary = shutil.which("teamviewer")
  installed = binary is not None or Path("/opt/teamviewer").exists()
  running = unit_active("teamviewerd.service", user=False)
  tv_id = teamviewer_id_from_logs()
  if not installed:
    status = "Not installed"
  elif running:
    status = "Online" if tv_id else "Daemon running"
  else:
    status = "Stopped"
  return {
    "installed": installed,
    "running": running,
    "id": tv_id,
    "statusText": status,
  }


def tailscale_ssh_status():
  ts = shutil.which("tailscale")
  user = os.environ.get("USER") or os.environ.get("LOGNAME") or ""
  result = {
    "installed": ts is not None,
    "enabled": False,
    "online": False,
    "user": user,
    "host": socket.gethostname().split(".")[0],
    "ip": "",
    "magicDns": "",
    "login": "",
    "command": "",
    "statusText": "Not installed",
  }
  if not ts:
    return result

  ip_code, ip_out = run([ts, "ip", "-4"], timeout=2)
  if ip_code == 0:
    result["ip"] = first_line(ip_out)

  ssh_on = False
  code, prefs = run([ts, "debug", "prefs"], timeout=3)
  if code == 0:
    try:
      data = json.loads(prefs)
      ssh_on = data.get("RunSSH") is True
    except json.JSONDecodeError:
      ssh_on = "\"RunSSH\": true" in prefs or "RunSSH: true" in prefs

  host = result["host"]
  magic = ""
  online = False
  code, status_raw = run([ts, "status", "--json", "--self"], timeout=3)
  if code != 0:
    code, status_raw = run([ts, "status", "--json"], timeout=3)
  if code == 0:
    try:
      data = json.loads(status_raw)
      self_node = data.get("Self") or {}
      host = str(self_node.get("HostName") or host)
      dns = str(self_node.get("DNSName") or "").rstrip(".")
      magic = dns
      online = self_node.get("Online") is True or str(data.get("BackendState") or "") == "Running"
      ips = self_node.get("TailscaleIPs") or []
      for item in ips:
        if str(item).startswith("100."):
          result["ip"] = str(item)
          break
    except json.JSONDecodeError:
      pass

  result["enabled"] = ssh_on
  result["online"] = online
  result["host"] = host
  result["magicDns"] = magic
  login = f"{user}@{host}" if user and host else host
  result["login"] = login
  result["command"] = f"tailscale ssh {login}" if login else ""
  if not online:
    result["statusText"] = "Offline"
  elif ssh_on:
    result["statusText"] = "SSH on"
  else:
    result["statusText"] = "SSH off"
  return result


def listening_ports():
  ports = set()
  code, out = run(["ss", "-tln"], timeout=2)
  if code != 0:
    return ports
  for line in out.splitlines():
    if "LISTEN" not in line:
      continue
    for match in SS_PORT_RE.findall(line):
      try:
        ports.add(int(match))
      except ValueError:
        pass
  return ports


def vnc_sessions():
  ports = listening_ports()
  sessions = []

  def add(name, address, url=""):
    sessions.append({
      "name": name,
      "address": address,
      "url": url,
      "running": True,
    })

  if unit_active("mac-mini-novnc.service") or 6080 in ports:
    add("Mac mini noVNC", "127.0.0.1:6080", "http://127.0.0.1:6080")
  if unit_active("wayvnc.service") or shutil.which("wayvnc") and 5900 in ports and not Path("/run/shm/qemu.pid").exists():
    # Prefer an explicit wayvnc unit; 5900 on this host is often QEMU.
    if unit_active("wayvnc.service"):
      add("WayVNC (this desktop)", "5900")
  if unit_active("vncserver@1.service") or 5901 in ports:
    add("TigerVNC display :1", ":5901")
  for display in range(0, 10):
    port = 5900 + display
    if port not in ports:
      continue
    if display == 0 and Path("/run/shm/qemu.pid").exists():
      add("QEMU VNC display :0", ":5900")
      continue
    if display == 1 and any(s["address"] == ":5901" for s in sessions):
      continue
    if display == 0 and any("WayVNC" in s["name"] for s in sessions):
      continue
    label = f"VNC display :{display}"
    if not any(s["address"] == f":{port}" or s["address"].endswith(f":{port}") for s in sessions):
      add(label, f":{port}")
  if 6901 in ports and not any("KasmVNC" in s["name"] for s in sessions):
    add("KasmVNC", ":6901", "http://127.0.0.1:6901")

  return sessions


def main():
  rustdesk = rustdesk_status()
  teamviewer = teamviewer_status()
  tailscale_ssh = tailscale_ssh_status()
  vnc = vnc_sessions()
  listening = rustdesk["running"] or teamviewer["running"] or tailscale_ssh["enabled"] or bool(vnc)
  print(json.dumps({
    "ok": True,
    "listening": listening,
    "rustdesk": rustdesk,
    "teamviewer": teamviewer,
    "tailscaleSsh": tailscale_ssh,
    "vnc": vnc,
  }))


if __name__ == "__main__":
  try:
    main()
  except Exception as exc:
    print(json.dumps({"ok": False, "lastError": str(exc)}))
    sys.exit(0)
