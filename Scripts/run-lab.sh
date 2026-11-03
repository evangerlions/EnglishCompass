#!/bin/bash
# Local Lab mode: builds a separate .app with its own Dock icon and settings.
# Usage: Scripts/run-lab.sh [--diff-demo]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/Scripts/build-lab.sh"
BIN="$ROOT/dist/English Compass Lab.app/Contents/MacOS/EnglishCompass"
# zsh -i sources ~/.zshrc; positional arguments keep paths/flags out of shell source.
exec zsh -ic 'exec "$@"' lab "$BIN" --lab "$@"
