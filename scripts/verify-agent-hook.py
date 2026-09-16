"""Exercise the packaged native adapter with synthetic events only."""
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as temp:
    target = Path(temp) / "events"
    identity = "11111111-1111-4111-8111-111111111111"
    payload = {"session_id": identity, "turn_id": "turn-1", "hook_event_name": "PermissionRequest",
               "tool_input": {"private": "DO_NOT_PERSIST"}, "prompt": "DO_NOT_PERSIST"}
    result = subprocess.run([sys.argv[1], str(target)], input=json.dumps(payload), text=True, capture_output=True, timeout=3)
    assert result.returncode == 0 and result.stdout == ""
    output = target / (identity + ".json")
    data = output.read_text()
    assert "DO_NOT_PERSIST" not in data
    assert json.loads(data)["event"] == "PermissionRequest"
    assert stat.S_IMODE(output.stat().st_mode) == 0o600
    assert stat.S_IMODE(target.stat().st_mode) == 0o700
    for bad in ["malformed", json.dumps({**payload, "session_id": "../../escape"}), json.dumps({**payload, "hook_event_name": "unsupported"})]:
        r = subprocess.run([sys.argv[1], str(target)], input=bad, text=True, capture_output=True, timeout=3)
        assert r.returncode == 0 and not r.stdout
    assert len(list(target.iterdir())) == 1
    print("Native event adapter: valid/invalid events, path validation, private permissions, no prompt persistence, no agent instructions: passed")
