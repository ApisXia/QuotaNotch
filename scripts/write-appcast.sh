#!/bin/bash
set -euo pipefail
# Signs the packaged DMG with the project's Sparkle EdDSA key and writes appcast.xml next to it.
# Run on macOS after scripts/package-quotanotch.sh. The private key comes from the
# SPARKLE_PRIVATE_KEY secret; it is written to a private temporary file and removed again.
dist='build/QuotaNotch-dist'
app='build/DerivedData/Build/Products/Release/QuotaNotch.app'
sparkle_version='2.10.1'
test -f "$dist/QuotaNotch.dmg"
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo '::error title=Sparkle::SPARKLE_PRIVATE_KEY is not set; a release without a signed appcast cannot update installed apps.'
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist" 2>/dev/null || echo 15.0)
public_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")
test -n "$public_key"

tools="${RUNNER_TEMP:-/tmp}/sparkle-tools"
mkdir -p "$tools"
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" -o "$tools/sparkle.tar.xz"
tar -xf "$tools/sparkle.tar.xz" -C "$tools"

key_file=$(mktemp "${RUNNER_TEMP:-/tmp}/sparkle-key.XXXXXX")
chmod 600 "$key_file"
trap 'rm -f "$key_file"' EXIT
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$key_file"
# Prints: sparkle:edSignature="..." length="..."
attributes=$("$tools/bin/sign_update" --ed-key-file "$key_file" "$dist/QuotaNotch.dmg")
rm -f "$key_file"

signature=$(sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' <<<"$attributes")
length=$(sed -E 's/.*length="([0-9]+)".*/\1/' <<<"$attributes")
test -n "$signature" && test -n "$length"

# The signature must verify against the public key the app ships with, or installed
# copies would reject the update.
python3 -m venv "$tools/venv"
"$tools/venv/bin/pip" install --quiet cryptography
"$tools/venv/bin/python" scripts/verify-update-signature.py "$dist/QuotaNotch.dmg" "$signature" "$public_key" \
  || { echo '::error title=Sparkle::The update signature does not match SUPublicEDKey in Info.plist.'; exit 1; }

python3 scripts/write-appcast.py "$version" "$build" "$minimum" "$signature" "$length" \
  "docs/Release-$version.md" > "$dist/appcast.xml"
echo "Wrote appcast for $version ($build)"
