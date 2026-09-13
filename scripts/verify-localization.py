#!/usr/bin/env python3
"""Validate actual compiled app translations, including dynamic quota messages."""
import json, plistlib, pathlib, sys, re
app = pathlib.Path(sys.argv[1])
catalog = json.loads(pathlib.Path("boringNotch/Localizable.xcstrings").read_text())["strings"]
for lang in ("en", "zh-Hans"):
    path = app / "Contents/Resources" / (lang + ".lproj/Localizable.strings")
    strings = plistlib.loads(path.read_bytes())
    for key, value in catalog.items():
        unit = value.get("localizations", {}).get(lang, {}).get("stringUnit")
        if value.get("extractionState") == "manual" and unit:
            assert strings.get(key) == unit["value"], (lang, key, strings.get(key))
    assert strings["AI 额度"] == ("AI Usage" if lang == "en" else "AI 额度")
    assert strings["日历"] == ("Calendar" if lang == "en" else "日历")
print("Compiled English and Simplified Chinese translations verified.")
