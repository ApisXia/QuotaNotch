#!/bin/bash
set -euo pipefail
# This release is explicitly authorized; a different version needs a new release decision.
[[ "$GITHUB_REF" == refs/heads/main || "$GITHUB_REF" == refs/heads/release/1.05-no-shelf ]]
grep -Fq 'MARKETING_VERSION = 1.05;' boringNotch.xcodeproj/project.pbxproj || exit 0
cd release-files
test "$(cat SOURCE-COMMIT.txt)" = "$GITHUB_SHA"
sha256sum -c SHA256SUMS.txt
python3 - <<'VERIFY'
import plistlib, zipfile
with zipfile.ZipFile('QuotaNotch.app.zip') as archive:
    info = plistlib.loads(archive.read('QuotaNotch.app/Contents/Info.plist'))
assert info['CFBundleShortVersionString'] == '1.05', info['CFBundleShortVersionString']
assert info['CFBundleVersion'] == '308', info['CFBundleVersion']
VERIFY
mv QuotaNotch.dmg QuotaNotch-1.05.dmg
mv QuotaNotch-source.zip QuotaNotch-1.05-source.zip
sha256sum QuotaNotch-1.05.dmg QuotaNotch.app.zip QuotaNotch-1.05-source.zip > SHA256SUMS.txt
if gh release view v1.05 --json isDraft --jq .isDraft > existing-draft.txt 2>/dev/null; then
  # Never overwrite an already public release.
  test "$(cat existing-draft.txt)" = true || exit 0
else
  gh release create v1.05 --target "$GITHUB_SHA" --title 'QuotaNotch 1.05' --notes-file ../docs/Release-1.05.md --draft
fi
# Public releases expose exactly three downloads: one DMG plus GitHub's automatic source ZIP and tar.gz.
# Keep alternate packages, checksums and build metadata in Actions artifacts only.
gh release upload v1.05 QuotaNotch-1.05.dmg --clobber
gh release edit v1.05 --draft=false --latest
