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
    for name in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]:
        r = subprocess.run([sys.argv[1], str(target)], input=json.dumps({**payload, "hook_event_name": name}), text=True, capture_output=True, timeout=3)
        assert r.returncode == 0 and r.stdout == ""
        assert json.loads(output.read_text())["event"] == name
        assert "DO_NOT_PERSIST" not in output.read_text()
    for bad in ["malformed", json.dumps({**payload, "session_id": "../../escape"}), json.dumps({**payload, "hook_event_name": "unsupported"})]:
        r = subprocess.run([sys.argv[1], str(target)], input=bad, text=True, capture_output=True, timeout=3)
        assert r.returncode == 0 and not r.stdout
    assert len(list(target.iterdir())) == 1
    print("Native event adapter: valid/invalid events, path validation, private permissions, no prompt persistence, no agent instructions: passed")

    # Status line mode: only rate-limit numbers are stored; chained output passes through.
    usage = Path(temp) / "usage"
    line = {"session_id": identity, "cwd": "/DO_NOT_PERSIST", "transcript_path": "/DO_NOT_PERSIST",
            "model": {"display_name": "DO_NOT_PERSIST"}, "cost": {"total_cost_usd": 1.5},
            "rate_limits": {"five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
                            "seven_day": {"used_percentage": 41.2, "resets_at": 1738857600}}}
    r = subprocess.run([sys.argv[1], "statusline", str(usage)], input=json.dumps(line), text=True, capture_output=True, timeout=3)
    assert r.returncode == 0 and r.stdout.strip() == "5h 77% left · 7d 59% left", r.stdout
    record = usage / (identity + ".json")
    saved = json.loads(record.read_text())
    assert "DO_NOT_PERSIST" not in record.read_text() and "cost" not in record.read_text()
    assert saved["rate_limits"]["five_hour"] == {"used_percentage": 23.5, "resets_at": 1738425600}
    assert stat.S_IMODE(record.stat().st_mode) == 0o600 and stat.S_IMODE(usage.stat().st_mode) == 0o700
    first = saved["observed_at"]
    r = subprocess.run([sys.argv[1], "statusline", str(usage), "cat >/dev/null; printf 'mine %s' \"$0\""],
                       input=json.dumps(line), text=True, capture_output=True, timeout=3)
    assert r.returncode == 0 and r.stdout.startswith("mine "), r.stdout
    assert json.loads(record.read_text())["observed_at"] == first, "unchanged numbers keep their time"
    r = subprocess.run([sys.argv[1], "statusline", str(usage), "exit 3"], input="not json", text=True, capture_output=True, timeout=3)
    assert r.returncode == 3 and r.stdout == ""
    no_limits = {k: v for k, v in line.items() if k != "rate_limits"}
    r = subprocess.run([sys.argv[1], "statusline", str(usage)], input=json.dumps({**no_limits, "session_id": "../x"}), text=True, capture_output=True, timeout=3)
    assert r.returncode == 0 and r.stdout == "" and len(list(usage.iterdir())) == 1
    print("Status line adapter: rate limits only, private permissions, change-only timestamps, chained output: passed")
