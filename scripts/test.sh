#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$source_root"

command -v omarchy >/dev/null 2>&1 || {
  echo "test.sh: omarchy is required" >&2
  exit 1
}

omarchy plugin validate .
python3 -m unittest discover -s tests -v

if [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  /usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell Model.js RemoteIcon.qml Service.qml Panel.qml || true
fi

python3 "$source_root/status.py" | python3 -c '
import json, sys
payload = json.load(sys.stdin)
assert payload.get("ok") is True, payload
assert "rustdesk" in payload and "teamviewer" in payload
assert "tailscaleSsh" in payload and "vnc" in payload
print("live status keys ok; listening=", payload.get("listening"))
'

echo "All validation and tests passed."
