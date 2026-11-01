#!/bin/bash
set -euo pipefail
# This release is explicitly authorized; a different version needs a new release decision.
test "$GITHUB_REF" = refs/heads/main
grep -Fq 'MARKETING_VERSION = 1.10;' boringNotch.xcodeproj/project.pbxproj || exit 0
cd release-files
test "$(cat SOURCE-COMMIT.txt)" = "$GITHUB_SHA"
sha256sum -c SHA256SUMS.txt
python3 - <<'VERIFY'
import plistlib, zipfile
with zipfile.ZipFile('QuotaNotch.app.zip') as archive:
    info = plistlib.loads(archive.read('QuotaNotch.app/Contents/Info.plist'))
assert info['CFBundleShortVersionString'] == '1.10', info['CFBundleShortVersionString']
assert info['CFBundleVersion'] == '320', info['CFBundleVersion']
VERIFY
mv QuotaNotch.dmg QuotaNotch-1.10.dmg
mv QuotaNotch-source.zip QuotaNotch-1.10-source.zip
sha256sum QuotaNotch-1.10.dmg QuotaNotch.app.zip QuotaNotch-1.10-source.zip > SHA256SUMS.txt
if gh release view v1.10 --json isDraft --jq .isDraft > existing-draft.txt 2>/dev/null; then
  # Never overwrite a public release.
  [[ "$(cat existing-draft.txt)" == true ]] || exit 0
else
  gh release create v1.10 --target "$GITHUB_SHA" --title 'QuotaNotch 1.10' --notes-file ../docs/Release-1.10.md --draft
fi
# Public releases expose one DMG (plus the appcast for in-app updates) and GitHub's automatic source archives.
# Keep alternate packages, checksums and build metadata in Actions artifacts only.
gh release upload v1.10 QuotaNotch-1.10.dmg --clobber
# Installed copies read appcast.xml from the latest release; it must be there before this one is.
if [[ -f appcast.xml ]]; then gh release upload v1.10 appcast.xml --clobber; fi
gh release edit v1.10 --draft=false --latest
