#!/usr/bin/env python3
"""Write a one-item Sparkle appcast for the current release.

The release notes come from docs/Release-<version>.md (a small Markdown subset).
"""
import html
import re
import sys
from datetime import datetime, timezone
from email.utils import format_datetime

version, build, minimum, signature, length, notes_path = sys.argv[1:7]
url = f"https://github.com/ApisXia/QuotaNotch/releases/download/v{version}/QuotaNotch-{version}.dmg"
page = f"https://github.com/ApisXia/QuotaNotch/releases/tag/v{version}"


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", text)


def notes_html(markdown):
    out, items = [], []

    def flush():
        if items:
            out.append("<ul>" + "".join(f"<li>{item}</li>" for item in items) + "</ul>")
            items.clear()

    for line in markdown.splitlines():
        line = line.rstrip()
        if line.startswith("- "):
            items.append(inline(line[2:]))
            continue
        flush()
        if not line:
            continue
        if line.startswith("#"):
            level = min(3, len(line) - len(line.lstrip("#")) + 1)
            out.append(f"<h{level}>{inline(line.lstrip('#').strip())}</h{level}>")
        elif line == "---":
            out.append("<hr>")
        else:
            out.append(f"<p>{inline(line)}</p>")
    flush()
    return "\n".join(out)


try:
    with open(notes_path, encoding="utf-8") as stream:
        notes = notes_html(stream.read())
except FileNotFoundError:
    notes = f'<p><a href="{page}">QuotaNotch {html.escape(version)}</a></p>'

style = "<style>body{font:13px -apple-system,sans-serif;line-height:1.45}h1{font-size:17px}h2{font-size:15px}</style>"
print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>QuotaNotch</title>
    <link>https://github.com/ApisXia/QuotaNotch/releases</link>
    <item>
      <title>QuotaNotch {html.escape(version)}</title>
      <pubDate>{format_datetime(datetime.now(timezone.utc))}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(minimum)}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{page}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{style}
{notes}]]></description>
      <enclosure url="{url}" sparkle:edSignature="{html.escape(signature)}" length="{html.escape(length)}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>""")
