#!/bin/bash
set -euo pipefail
# Run at repository root on macOS after the Release build. No Apple signing secrets.
app='build/DerivedData/Build/Products/Release/QuotaNotch.app'
dist='build/QuotaNotch-dist'
staging='build/QuotaNotch-dmg'
test -d "$app"
mkdir -p "$dist" "$staging"
# Ad-hoc sign embedded code from the inside out. This is NOT notarization.
python3 scripts/sign-quotanotch.py "$app"
codesign --verify --deep --strict --verbose=2 "$app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = 'com.apisxia.quotanotch'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app/Contents/Info.plist")" = 'QuotaNotch'
if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app/Contents/Info.plist" 2>/dev/null; then
  echo 'Unexpected upstream update feed' >&2
  exit 1
fi
lipo "$app/Contents/MacOS/QuotaNotch" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/QuotaNotch.app.zip"
ditto "$app" "$staging/QuotaNotch.app"
ln -s /Applications "$staging/Applications"
cp README.zh-CN.md "$staging/安装与使用.md"
cp LICENSE "$staging/LICENSE"
git archive --format=zip --prefix=QuotaNotch-source/ -o "$dist/QuotaNotch-source.zip" HEAD
cp "$dist/QuotaNotch-source.zip" "$staging/QuotaNotch-source.zip"
hdiutil create -volname QuotaNotch -srcfolder "$staging" -ov -format UDZO "$dist/QuotaNotch.dmg"
git rev-parse HEAD > "$dist/SOURCE-COMMIT.txt"
cp README.zh-CN.md "$dist/README-zh.md"
cp LICENSE THIRD_PARTY_LICENSES "$dist/"
(cd "$dist" && shasum -a 256 QuotaNotch.dmg QuotaNotch.app.zip QuotaNotch-source.zip > SHA256SUMS.txt)
