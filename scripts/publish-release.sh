#!/bin/bash
set -euo pipefail
# This release is explicitly authorized; a different version needs a new release decision.
test "$GITHUB_REF" = refs/heads/main
grep -Fq 'MARKETING_VERSION = 1.06;' boringNotch.xcodeproj/project.pbxproj || exit 0
cd release-files
test "$(cat SOURCE-COMMIT.txt)" = "$GITHUB_SHA"
sha256sum -c SHA256SUMS.txt
python3 - <<'VERIFY'
import plistlib, zipfile
with zipfile.ZipFile('QuotaNotch.app.zip') as archive:
    info = plistlib.loads(archive.read('QuotaNotch.app/Contents/Info.plist'))
assert info['CFBundleShortVersionString'] == '1.06', info['CFBundleShortVersionString']
assert info['CFBundleVersion'] == '309', info['CFBundleVersion']
VERIFY
mv QuotaNotch.dmg QuotaNotch-1.06.dmg
mv QuotaNotch-source.zip QuotaNotch-1.06-source.zip
sha256sum QuotaNotch-1.06.dmg QuotaNotch.app.zip QuotaNotch-1.06-source.zip > SHA256SUMS.txt
if gh release view v1.06 --json isDraft --jq .isDraft > existing-draft.txt 2>/dev/null; then
  # Never overwrite an already public release.
  test "$(cat existing-draft.txt)" = true || exit 0
else
  gh release create v1.06 --target "$GITHUB_SHA" --title 'QuotaNotch 1.06' --notes-file ../docs/Release-1.06.md --draft
fi
# Public releases expose exactly three downloads: one DMG plus GitHub's automatic source ZIP and tar.gz.
# Keep alternate packages, checksums and build metadata in Actions artifacts only.
gh release upload v1.06 QuotaNotch-1.06.dmg --clobber
gh release edit v1.06 --draft=false --latest
