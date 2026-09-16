#!/bin/bash
set -euo pipefail
# This release is explicitly authorized; a different version needs a new release decision.
test "$GITHUB_REF" = refs/heads/main
grep -Fq 'MARKETING_VERSION = 1.02;' boringNotch.xcodeproj/project.pbxproj || exit 0
cd release-files
test "$(cat SOURCE-COMMIT.txt)" = "$GITHUB_SHA"
sha256sum -c SHA256SUMS.txt
python3 - <<'VERIFY'
import plistlib, zipfile
with zipfile.ZipFile('QuotaNotch.app.zip') as archive:
    info = plistlib.loads(archive.read('QuotaNotch.app/Contents/Info.plist'))
assert info['CFBundleShortVersionString'] == '1.02', info['CFBundleShortVersionString']
assert info['CFBundleVersion'] == '279', info['CFBundleVersion']
VERIFY
mv QuotaNotch.dmg QuotaNotch-1.02.dmg
mv QuotaNotch-source.zip QuotaNotch-1.02-source.zip
sha256sum QuotaNotch-1.02.dmg QuotaNotch.app.zip QuotaNotch-1.02-source.zip > SHA256SUMS.txt
if gh release view v1.02 --json isDraft --jq .isDraft > existing-draft.txt 2>/dev/null; then
  # Never overwrite an already public release.
  test "$(cat existing-draft.txt)" = true || exit 0
else
  gh release create v1.02 --target "$GITHUB_SHA" --title 'QuotaNotch 1.02' --notes-file ../docs/Release-1.02.md --draft
fi
gh release upload v1.02 QuotaNotch-1.02.dmg --clobber
gh release edit v1.02 --draft=false --latest
