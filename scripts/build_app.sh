#!/usr/bin/env bash
# Builds ScreenCapture.app into ./build without Xcode.
#   CONFIG=debug ./scripts/build_app.sh          # unoptimised build
#   SIGN_IDENTITY="Apple Development: …" ./scripts/build_app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="$ROOT/build/ScreenCapture.app"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"

OPT="-O"
[[ "$CONFIG" == "debug" ]] && OPT="-Onone -g"

echo "› Compiling ($CONFIG, $ARCH)…"
mkdir -p "$ROOT/.build/app"
# shellcheck disable=SC2046
swiftc -swift-version 6 $OPT -wmo \
    -target "$ARCH-apple-macos26.0" -sdk "$SDK" \
    -framework AVKit \
    $(find "$ROOT/Sources/ScreenCapture" -name '*.swift') \
    -o "$ROOT/.build/app/ScreenCapture"

echo "› Bundling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/app/ScreenCapture" "$APP/Contents/MacOS/ScreenCapture"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

ICONSET="$ROOT/.build/AppIcon.iconset"
if [[ ! -f "$ROOT/.build/AppIcon.icns" ]]; then
    echo "› Rendering icon…"
    rm -rf "$ICONSET"
    swift "$ROOT/scripts/make_icon.swift" "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ROOT/.build/AppIcon.icns"
fi
cp "$ROOT/.build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "› Signing ($SIGN_IDENTITY)…"
codesign --force --sign "$SIGN_IDENTITY" --identifier dev.local.ScreenCapture "$APP"

echo "✓ Built $APP"
