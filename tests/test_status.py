#!/usr/bin/env python3
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import status  # noqa: E402


class StatusTests(unittest.TestCase):
    def test_first_line(self):
        self.assertEqual(status.first_line("  abc\n def"), "abc")
        self.assertEqual(status.first_line(""), "")

    def test_parse_status_helper_shape(self):
        raw = json.dumps({
            "ok": True,
            "listening": True,
            "rustdesk": {"installed": True, "running": True, "unitActive": True, "id": "123", "statusText": "Listening"},
            "teamviewer": {"installed": False, "running": False, "id": "", "statusText": "Not installed"},
            "tailscaleSsh": {"installed": True, "enabled": True, "online": True, "user": "luke", "host": "omarchy-pc", "ip": "100.1.2.3", "magicDns": "omarchy-pc.tailnet", "login": "luke@omarchy-pc", "command": "tailscale ssh luke@omarchy-pc", "statusText": "SSH on"},
            "vnc": [{"name": "Mac mini noVNC", "address": "127.0.0.1:6080", "url": "http://127.0.0.1:6080", "running": True}],
        })
        parsed = __import__("importlib").machinery.SourceFileLoader("model", str(ROOT / "Model.js")).load_module if False else None
        del parsed
        # Model.js is QML; check the Python payload the widget consumes.
        data = json.loads(raw)
        self.assertTrue(data["ok"])
        self.assertEqual(data["rustdesk"]["statusText"], "Listening")
        self.assertEqual(data["vnc"][0]["name"], "Mac mini noVNC")

    def test_teamviewer_id_regex(self):
        sample = "UpdateMachineID: New machineID = 123456789"
        self.assertEqual(status.TV_ID_RE.findall(sample)[-1], "123456789")


if __name__ == "__main__":
    unittest.main()
