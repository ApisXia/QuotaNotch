#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROTOTYPE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$PROTOTYPE_DIR/NativeBubbleMaterial/Sources"
OUTPUT_DIR="${1:-$PROTOTYPE_DIR/output}"
BUILD_DIR="$OUTPUT_DIR/build"
APP_DIR="$OUTPUT_DIR/BubbleMaterialLab.app"
APP_CONTENTS="$APP_DIR/Contents"

mkdir -p "$BUILD_DIR" "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources" "$OUTPUT_DIR/rendered"

echo "Xcode toolchain:"
xcodebuild -version
echo "Swift toolchain:"
swift --version

xcrun --sdk macosx metal -c "$SOURCE_DIR/BubbleFilm.metal" -o "$BUILD_DIR/BubbleFilm.air"
xcrun --sdk macosx metallib "$BUILD_DIR/BubbleFilm.air" -o "$APP_CONTENTS/Resources/default.metallib"
cp "$PROTOTYPE_DIR/NativeBubbleMaterial/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$PROTOTYPE_DIR/NativeBubbleMaterial/Resources/DemoStillLife.png" "$APP_CONTENTS/Resources/DemoStillLife.png"
printf 'APPL????' > "$APP_CONTENTS/PkgInfo"

SWIFT_SOURCES=(
  "$SOURCE_DIR/App.swift"
  "$SOURCE_DIR/BubbleContent.swift"
  "$SOURCE_DIR/BubbleChecks.swift"
  "$SOURCE_DIR/BubbleMotion.swift"
  "$SOURCE_DIR/BubbleScene.swift"
  "$SOURCE_DIR/NotchAppearanceDemo.swift"
  "$SOURCE_DIR/NativeCapture.swift"
)

for architecture in arm64 x86_64; do
  xcrun --sdk macosx swiftc \
    -target "$architecture-apple-macos14.0" \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -framework SwiftUI \
    -framework AppKit \
    -framework Metal \
    -framework AVFoundation \
    -framework CoreVideo \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_DIR/BubbleMaterialLab-$architecture"
done

lipo -create \
  "$BUILD_DIR/BubbleMaterialLab-arm64" \
  "$BUILD_DIR/BubbleMaterialLab-x86_64" \
  -output "$APP_CONTENTS/MacOS/BubbleMaterialLab"
codesign --force --deep --sign - "$APP_DIR"

"$APP_CONTENTS/MacOS/BubbleMaterialLab" --self-test
"$APP_CONTENTS/MacOS/BubbleMaterialLab" --capture "$OUTPUT_DIR/rendered"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$OUTPUT_DIR/BubbleMaterialLab-macOS.zip"
echo "Native app and Metal render evidence written to $OUTPUT_DIR"
