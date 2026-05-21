#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_BIN="${NURL_BUILD_BIN:-$SCRIPT_DIR/build/nurl-build}"
ZIG_BIN="${NURL_ZIG:-zig}"

cd "$SCRIPT_DIR"

if [[ ! -x "$HELPER_BIN" ]]; then
    "$ZIG_BIN" build nurl-build
fi

exec "$HELPER_BIN" startdev "$@"
