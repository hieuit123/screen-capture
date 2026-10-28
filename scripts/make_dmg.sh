#!/usr/bin/env bash
# Builds ScreenCapture.app and packages it into build/ScreenCapture-<version>.dmg
#   SKIP_BUILD=1 ./scripts/make_dmg.sh   # package the existing build/ScreenCapture.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ScreenCapture.app"

[[ "${SKIP_BUILD:-0}" == "1" ]] || "$ROOT/scripts/build_app.sh"
[[ -d "$APP" ]] || { echo "Missing $APP"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/ScreenCapture-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "› Staging…"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "› Creating ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "ScreenCapture" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
codesign --force --sign "${SIGN_IDENTITY:--}" "$DMG"
hdiutil verify "$DMG" >/dev/null

echo "✓ Built $DMG ($(du -h "$DMG" | cut -f1))"
