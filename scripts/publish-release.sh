#!/bin/bash
set -euo pipefail
# This release is explicitly authorized; a different version needs a new release decision.
test "$GITHUB_REF" = refs/heads/main
grep -Fq 'MARKETING_VERSION = 1.08;' boringNotch.xcodeproj/project.pbxproj || exit 0
cd release-files
test "$(cat SOURCE-COMMIT.txt)" = "$GITHUB_SHA"
sha256sum -c SHA256SUMS.txt
python3 - <<'VERIFY'
import plistlib, zipfile
with zipfile.ZipFile('QuotaNotch.app.zip') as archive:
    info = plistlib.loads(archive.read('QuotaNotch.app/Contents/Info.plist'))
assert info['CFBundleShortVersionString'] == '1.08', info['CFBundleShortVersionString']
assert info['CFBundleVersion'] == '312', info['CFBundleVersion']
VERIFY
mv QuotaNotch.dmg QuotaNotch-1.08.dmg
mv QuotaNotch-source.zip QuotaNotch-1.08-source.zip
sha256sum QuotaNotch-1.08.dmg QuotaNotch.app.zip QuotaNotch-1.08-source.zip > SHA256SUMS.txt
if gh release view v1.08 --json isDraft --jq .isDraft > existing-draft.txt 2>/dev/null; then
  if [[ "$(cat existing-draft.txt)" != true ]]; then
    # Never overwrite a public release, with one authorized exception: 1.08 (311) is replaced
    # in place by 1.08 (312). Installed 311 copies update to it because its build is higher.
    gh release download v1.08 -p appcast.xml -O published-appcast.xml
    grep -Fq '<sparkle:version>311</sparkle:version>' published-appcast.xml || exit 0
    gh release delete v1.08 --cleanup-tag --yes
    gh release create v1.08 --target "$GITHUB_SHA" --title 'QuotaNotch 1.08' --notes-file ../docs/Release-1.08.md --draft
  fi
else
  gh release create v1.08 --target "$GITHUB_SHA" --title 'QuotaNotch 1.08' --notes-file ../docs/Release-1.08.md --draft
fi
# Public releases expose one DMG (plus the appcast for in-app updates) and GitHub's automatic source archives.
# Keep alternate packages, checksums and build metadata in Actions artifacts only.
gh release upload v1.08 QuotaNotch-1.08.dmg --clobber
# Installed copies read appcast.xml from the latest release; it must be there before this one is.
if [[ -f appcast.xml ]]; then gh release upload v1.08 appcast.xml --clobber; fi
gh release edit v1.08 --draft=false --latest
