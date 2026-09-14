#!/bin/bash
set -euo pipefail
# Only the first stable release is authorized here; later versions need their own release decision.
test "$GITHUB_REF" = refs/heads/main
grep -q 'MARKETING_VERSION = 1.0.0;' boringNotch.xcodeproj/project.pbxproj || exit 0
cd release-files
test "$(cat SOURCE-COMMIT.txt)" = "$GITHUB_SHA"
sha256sum -c SHA256SUMS.txt
mv QuotaNotch.dmg QuotaNotch-1.0.0.dmg
mv QuotaNotch-source.zip QuotaNotch-1.0.0-source.zip
sha256sum QuotaNotch-1.0.0.dmg QuotaNotch.app.zip QuotaNotch-1.0.0-source.zip > SHA256SUMS.txt
if gh release view v1.0.0 --json isDraft --jq .isDraft > existing-draft.txt 2>/dev/null; then
  # Never overwrite an already public release.
  test "$(cat existing-draft.txt)" = true || exit 0
else
  gh release create v1.0.0 --target "$GITHUB_SHA" --title 'QuotaNotch 1.0.0' --notes-file ../docs/Release-1.0.0.md --draft
fi
gh release upload v1.0.0 QuotaNotch-1.0.0.dmg QuotaNotch.app.zip QuotaNotch-1.0.0-source.zip SHA256SUMS.txt SOURCE-COMMIT.txt LICENSE THIRD_PARTY_LICENSES --clobber
gh release edit v1.0.0 --draft=false --latest
