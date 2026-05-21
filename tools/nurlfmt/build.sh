#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/nurlfmt/build.sh — build the nurlfmt formatter binary.
#
#  Stage:
#    1. Compile tools/nurlfmt/nurlfmt.nu to LLVM IR using ./build/nurlc
#    2. Link with stdlib/runtime.o → ./build/nurlfmt
#
#  Requires that ./build.sh has already run (so build/nurlc and
#  stdlib/runtime.o exist).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

NURLC="$ROOT_DIR/build/nurlc"
RUNTIME="$ROOT_DIR/stdlib/runtime.o"
SRC="$ROOT_DIR/tools/nurlfmt/nurlfmt.nu"

if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: $NURLC not found." >&2
    echo "       Run ./build.sh first to bootstrap the compiler." >&2
    exit 1
fi
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: $RUNTIME not found." >&2
    echo "       Run ./build.sh first to compile the runtime." >&2
    exit 1
fi

mkdir -p "$ROOT_DIR/build"

echo "[1/2] $SRC → build/nurlfmt.ll"
"$NURLC" "$SRC" > "$ROOT_DIR/build/nurlfmt.ll"

echo "[2/2] build/nurlfmt.ll → build/nurlfmt"
"$ROOT_DIR/tools/nurl-build/run.sh" "$ROOT_DIR" "$ROOT_DIR/build/nurlfmt.ll" "$ROOT_DIR/build/nurlfmt"

echo ""
echo "Done: $ROOT_DIR/build/nurlfmt"
