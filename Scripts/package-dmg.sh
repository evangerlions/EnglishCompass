#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT/dist/EnglishCompass-Installer.dmg}"
IDENTITY="${SIGNING_IDENTITY:--}"
APP_SIGN_ARGS=(--force --sign "$IDENTITY")
DMG_SIGN_ARGS=(--sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then
  APP_SIGN_ARGS+=(--options runtime --timestamp)
  DMG_SIGN_ARGS+=(--timestamp)
fi
STAGE=$(mktemp -d /private/tmp/EnglishCompass-dmg.XXXXXX)
trap 'find "$STAGE" -depth -delete' EXIT
mkdir -p "$(dirname "$OUTPUT")"
ditto --norsrc --noextattr "$ROOT/dist/English Compass.app" "$STAGE/English Compass.app"
xattr -cr "$STAGE/English Compass.app"
codesign "${APP_SIGN_ARGS[@]}" "$STAGE/English Compass.app"
codesign --verify --deep --strict "$STAGE/English Compass.app"
swift "$ROOT/Scripts/dmg-background.swift" "$STAGE/background.png"
# Default to the standard system Applications folder; local testing may override it.
uvx --from dmgbuild==1.6.7 dmgbuild -s "$ROOT/Scripts/dmg-settings.py" \
  -D "app=$STAGE/English Compass.app" -D "background=$STAGE/background.png" \
  -D "applications=${APPLICATIONS_TARGET:-/Applications}" \
  "English Compass" "$OUTPUT"
codesign "${DMG_SIGN_ARGS[@]}" "$OUTPUT"
codesign --verify "$OUTPUT"
hdiutil verify "$OUTPUT"
printf 'Installer created: %s\n' "$OUTPUT"
