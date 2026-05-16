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

CLANG="${CLANG:-clang}"
if ! command -v "$CLANG" >/dev/null 2>&1; then
    echo "ERROR: clang not on PATH (set CLANG=/path/to/clang to override)." >&2
    exit 1
fi

mkdir -p "$ROOT_DIR/build"

echo "[1/2] $SRC → build/nurl-lsp.ll"
"$NURLC" "$SRC" > "$ROOT_DIR/build/nurl-lsp.ll"

# Match build.sh's link line — runtime.o was compiled with whatever
# back-ends were detected at build time; the marker files tell us
# which libs we need to add.
EXTRA_LIBS=()
if [[ -f "$ROOT_DIR/stdlib/runtime.curl" ]]; then
    if pkg-config --exists libcurl 2>/dev/null; then
        # shellcheck disable=SC2207
        EXTRA_LIBS+=( $(pkg-config --libs libcurl) )
    else
        EXTRA_LIBS+=( -lcurl )
    fi
fi
if [[ -f "$ROOT_DIR/stdlib/runtime.openssl" ]]; then
    if pkg-config --exists openssl 2>/dev/null; then
        # shellcheck disable=SC2207
        EXTRA_LIBS+=( $(pkg-config --libs openssl) )
    else
        EXTRA_LIBS+=( -lssl -lcrypto )
    fi
fi
if [[ -f "$ROOT_DIR/stdlib/runtime.sqlite3" ]]; then
    if pkg-config --exists sqlite3 2>/dev/null; then
        # shellcheck disable=SC2207
        EXTRA_LIBS+=( $(pkg-config --libs sqlite3) )
    else
        EXTRA_LIBS+=( -lsqlite3 )
    fi
fi
if [[ -f "$ROOT_DIR/stdlib/runtime.pq" ]]; then
    if pkg-config --exists libpq 2>/dev/null; then
        # shellcheck disable=SC2207
        EXTRA_LIBS+=( $(pkg-config --libs libpq) )
    else
        EXTRA_LIBS+=( -lpq )
    fi
fi

echo "[2/2] build/nurl-lsp.ll → build/nurl-lsp"
"$CLANG" -O2 -flto "$ROOT_DIR/build/nurl-lsp.ll" "$RUNTIME" -lm -lpthread "${EXTRA_LIBS[@]}" -o "$ROOT_DIR/build/nurl-lsp"

echo ""
echo "Done: $ROOT_DIR/build/nurl-lsp"
