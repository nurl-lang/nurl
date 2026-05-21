#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ZIG_BIN="${NURL_ZIG:-zig}"

cd "$ROOT_DIR"
exec "$ZIG_BIN" build san-test -Dsan=true -- "$@"
