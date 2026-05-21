#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $# -ne 0 ]]; then
    echo "build_lastgood.sh does not accept arguments." >&2
    echo "Run: zig build bootstrap-lastgood" >&2
    exit 2
fi

ZIG_BIN="${NURL_ZIG:-zig}"
exec "$ZIG_BIN" build bootstrap-lastgood
