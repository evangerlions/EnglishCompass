#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/dist/English Compass.app"
DEST="$HOME/Applications/English Compass.app"
if [ ! -d "$SOURCE" ]; then bash "$ROOT/Scripts/build-app.sh"; fi
if [ -d "$DEST" ]; then
    ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")
    if [ "$ID" != 'com.zook.EnglishCompass' ]; then printf 'Refusing to replace a different app.\n'; exit 1; fi
fi
mkdir -p "$HOME/Applications"
ditto --norsrc --noextattr "$SOURCE" "$DEST"
for directory in "$DEST/Contents/Resources/Backend" "$DEST/Contents/Resources/Scripts"; do
    if [ -e "$directory" ] || [ -L "$directory" ]; then find "$directory" -depth -delete; fi
done
xattr -cr "$DEST"
codesign --force --sign - "$DEST"
codesign --verify --deep --strict "$DEST"
printf 'Installed outside iCloud-managed Documents: %s\n' "$DEST"
