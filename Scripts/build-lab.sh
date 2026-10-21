#!/bin/bash
# Build a separate Debug .app so Lab has its own Dock identity and app icon.
# This does not install or modify the release app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build --disable-sandbox >/dev/null
BIN="$(swift build --show-bin-path --disable-sandbox)/EnglishCompass"
APP="$ROOT/dist/English Compass Lab.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EnglishCompass"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.zook.EnglishCompass.lab' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName English Compass Lab' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon-imagegen-v2.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Lab built: %s\n' "$APP"
