#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ZIG_BIN="${NURL_ZIG:-zig}"
exec "$ZIG_BIN" build install-dev -- "$@"
