#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/nurl-lsp/build.sh — build the nurl-lsp Language Server
#  binary.
#
#  Stage:
#    1. Compile tools/nurl-lsp/main.nu to LLVM IR using ./build/nurlc
#    2. Link with stdlib/runtime.o → ./build/nurl-lsp
#
#  Requires that ./build.sh has already run.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

NURLC="$ROOT_DIR/build/nurlc"
RUNTIME="$ROOT_DIR/stdlib/runtime.o"
SRC="$ROOT_DIR/tools/nurl-lsp/main.nu"

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

echo "[1/2] $SRC → build/nurl-lsp.ll"
"$NURLC" "$SRC" > "$ROOT_DIR/build/nurl-lsp.ll"

echo "[2/2] build/nurl-lsp.ll → build/nurl-lsp"
"$ROOT_DIR/tools/nurl-build/run.sh" "$ROOT_DIR" "$ROOT_DIR/build/nurl-lsp.ll" "$ROOT_DIR/build/nurl-lsp"

echo ""
echo "Done: $ROOT_DIR/build/nurl-lsp"
