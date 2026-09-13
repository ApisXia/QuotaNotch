#!/bin/bash
set -euo pipefail
preview='build/LanguagePreview.app'
mkdir -p "$preview/Contents/MacOS" "$preview/Contents/Resources"
cp -R build/DerivedData/Build/Products/Release/QuotaNotch.app/Contents/Resources/en.lproj "$preview/Contents/Resources/"
cp -R build/DerivedData/Build/Products/Release/QuotaNotch.app/Contents/Resources/zh-Hans.lproj "$preview/Contents/Resources/"
cat > "$preview/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.apisxia.quotanotch.languagepreview</string>
<key>CFBundleExecutable</key><string>LanguagePreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
swiftc -target "$(uname -m)-apple-macos15.0" -parse-as-library QuotaNotch/Design/*.swift QuotaNotch/Core/QuotaCompactMetrics.swift QuotaNotch/Core/QuotaLocalization.swift QuotaNotch/Core/QuotaModels.swift scripts/render-usage.swift -o "$preview/Contents/MacOS/LanguagePreview"
"$preview/Contents/MacOS/LanguagePreview" -AppleLanguages '(en)' build/QuotaNotch-dist/Usage-English.png
"$preview/Contents/MacOS/LanguagePreview" -AppleLanguages '(zh-Hans)' build/QuotaNotch-dist/Usage-Chinese.png
