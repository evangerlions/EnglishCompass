#!/usr/bin/env bash
# Local latency benchmark. Run from an interactive shell so BAILIAN_API_KEY
# from ~/.zshrc is visible. Usage: ./Scripts/bench.sh [runs]
set -euo pipefail
cd "$(dirname "$0")/.."
RUNS="${1:-5}"
swift run --disable-sandbox ECBench "$RUNS"
