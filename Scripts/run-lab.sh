#!/bin/bash
# Local Lab mode: builds a separate .app with its own Dock icon and settings.
# Usage: Scripts/run-lab.sh [--diff-demo]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/Scripts/build-lab.sh"
BIN="$ROOT/dist/English Compass Lab.app/Contents/MacOS/EnglishCompass"
# Diff-only mode needs neither the model key nor the interactive shell.
if [[ "${1:-}" == "--diff-demo" ]]; then
    exec "$BIN" --lab --diff-demo
fi
# zsh -i sources ~/.zshrc; positional arguments keep paths/flags out of shell source.
exec zsh -ic 'exec "$@"' lab "$BIN" --lab "$@"
