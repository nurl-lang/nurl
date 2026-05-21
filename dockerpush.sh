#!/usr/bin/env bash
# Build the API image and push it to Docker Hub under hindurable/nurl:latest.
# Run from the repo root. Requires `docker login` to have been done once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_BIN="${NURL_BUILD_BIN:-$SCRIPT_DIR/build/nurl-build}"
ZIG_BIN="${NURL_ZIG:-zig}"

cd "$SCRIPT_DIR"

if [[ ! -x "$HELPER_BIN" ]]; then
    "$ZIG_BIN" build nurl-build
fi

exec "$HELPER_BIN" dockerpush "$@"
