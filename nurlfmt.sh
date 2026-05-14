#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  nurlfmt.sh — thin launcher for the NURL canonical formatter.
#
#  Usage:  ./nurlfmt.sh [OPTIONS] [FILE...]
#
#  Forwards all arguments to ./build/nurlfmt. Builds the binary on
#  first run via tools/nurlfmt/build.sh if it is missing.
#
#  See docs/FORMAT.md for the formatting specification and the full
#  CLI surface.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NURLFMT="$SCRIPT_DIR/build/nurlfmt"

if [[ ! -x "$NURLFMT" ]]; then
    echo "[nurlfmt.sh] build/nurlfmt missing — bootstrapping..." >&2
    bash "$SCRIPT_DIR/tools/nurlfmt/build.sh"
fi

exec "$NURLFMT" "$@"
