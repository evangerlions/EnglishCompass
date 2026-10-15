#!/bin/bash
# Local Lab mode: launches the test window with the key from ~/.zshrc.
# Usage: Scripts/run-lab.sh
# Never run this against a release build; swift build uses the debug one.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build --disable-sandbox >/dev/null
BIN="$(swift build --show-bin-path --disable-sandbox)/EnglishCompass"
# zsh -i sources ~/.zshrc, so BAILIAN_API_KEY is visible; exec replaces the shell.
exec zsh -ic "exec '$BIN' --lab"
