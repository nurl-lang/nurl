#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/nurlpkg/build.sh — build the nurlpkg package manager
#  binary.
#
#  Stage:
#    1. Compile tools/nurlpkg/main.nu to LLVM IR using ./build/nurlc
#    2. Link with stdlib/runtime.o → ./build/nurlpkg
#
#  Requires that ./build.sh has already run.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

NURLC="$ROOT_DIR/build/nurlc"
RUNTIME="$ROOT_DIR/stdlib/runtime.o"
SRC="$ROOT_DIR/tools/nurlpkg/main.nu"

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

echo "[1/2] $SRC → build/nurlpkg.ll"
"$NURLC" "$SRC" > "$ROOT_DIR/build/nurlpkg.ll"

# Match the central build.sh runtime link line — runtime.o was built
# with whichever back-ends were detected at build time, and the
# linker needs the same libraries.
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
if [[ -f "$ROOT_DIR/stdlib/runtime.z" ]]; then
    if pkg-config --exists zlib 2>/dev/null; then
        # shellcheck disable=SC2207
        EXTRA_LIBS+=( $(pkg-config --libs zlib) )
    else
        EXTRA_LIBS+=( -lz )
    fi
fi
if [[ -f "$ROOT_DIR/stdlib/runtime.zstd" ]]; then
    if pkg-config --exists libzstd 2>/dev/null; then
        # shellcheck disable=SC2207
        EXTRA_LIBS+=( $(pkg-config --libs libzstd) )
    else
        EXTRA_LIBS+=( -lzstd )
    fi
fi

echo "[2/2] build/nurlpkg.ll → build/nurlpkg"
"$CLANG" -O2 -flto "$ROOT_DIR/build/nurlpkg.ll" "$RUNTIME" -lm -lpthread "${EXTRA_LIBS[@]}" -o "$ROOT_DIR/build/nurlpkg"

echo ""
echo "Done: $ROOT_DIR/build/nurlpkg"
