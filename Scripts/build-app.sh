#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_ARGS=(-c release)
if [ -n "${SWIFT_BUILD_PATH:-}" ]; then
    BUILD_ARGS+=(--scratch-path "$SWIFT_BUILD_PATH")
fi
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP="$ROOT/dist/English Compass.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/EnglishCompass" "$APP/Contents/MacOS/EnglishCompass"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
ICONSET=$(mktemp -d)/AppIcon.iconset
swift "$ROOT/Scripts/app-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
for directory in "$APP/Contents/Resources/Backend" "$APP/Contents/Resources/Scripts"; do
    if [ -e "$directory" ] || [ -L "$directory" ]; then find "$directory" -depth -delete; fi
done
xattr -cr "$APP"
codesign --force --sign - "$APP"
printf 'App built: %s\n' "$APP"
