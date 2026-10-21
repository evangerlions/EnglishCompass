#!/bin/bash
# Local Lab mode: builds a separate .app with its own Dock icon and settings.
# Usage: Scripts/run-lab.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/Scripts/build-lab.sh"
BIN="$ROOT/dist/English Compass Lab.app/Contents/MacOS/EnglishCompass"
# zsh -i sources ~/.zshrc, so BAILIAN_API_KEY is visible; exec replaces the shell.
exec zsh -ic "exec '$BIN' --lab"
