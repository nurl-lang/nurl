#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Shared link helper for repo-local NURL tooling binaries.
# Prefers the Zig implementation when `zig` is available; otherwise
# falls back to a shell implementation with the same link policy.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <repo-root> <llvm-ir> <output-bin>" >&2
    exit 2
fi

ROOT_DIR="$1"
LLVM_IR="$2"
OUTPUT_BIN="$3"
RUNTIME="$ROOT_DIR/stdlib/runtime.o"

if [[ ! -f "$LLVM_IR" ]]; then
    echo "ERROR: LLVM IR not found at $LLVM_IR" >&2
    exit 1
fi
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: runtime.o not found at $RUNTIME" >&2
    echo "       Run ./build.sh first to compile the runtime." >&2
    exit 1
fi

ZIG_BIN="${NURL_ZIG:-zig}"
if command -v "$ZIG_BIN" >/dev/null 2>&1; then
    mkdir -p "$ROOT_DIR/.zig-cache" "$ROOT_DIR/.zig-cache-global"
    exec env \
        ZIG_LOCAL_CACHE_DIR="$ROOT_DIR/.zig-cache" \
        ZIG_GLOBAL_CACHE_DIR="$ROOT_DIR/.zig-cache-global" \
        "$ZIG_BIN" run "$ROOT_DIR/tools/nurl-build/main.zig" -- "$ROOT_DIR" "$LLVM_IR" "$OUTPUT_BIN"
fi

read -r -a CC <<< "${NURL_CC:-${CLANG:-clang}}"
if ! command -v "${CC[0]}" >/dev/null 2>&1; then
    echo "ERROR: C driver '${CC[*]}' not found." >&2
    exit 1
fi

LTO_FLAG="-flto"
if [[ -f "$ROOT_DIR/stdlib/runtime.nolto" ]]; then
    LTO_FLAG=""
fi

EXTRA_LIBS=()
append_libs_from_marker() {
    local marker="$1"
    local pkg="$2"
    shift 2
    if [[ ! -f "$ROOT_DIR/stdlib/$marker" ]]; then
        return
    fi
    if pkg-config --exists "$pkg" 2>/dev/null; then
        # shellcheck disable=SC2207
        EXTRA_LIBS+=( $(pkg-config --libs "$pkg") )
    else
        EXTRA_LIBS+=( "$@" )
    fi
}

append_libs_from_marker "runtime.curl" "libcurl" -lcurl
append_libs_from_marker "runtime.openssl" "openssl" -lssl -lcrypto
append_libs_from_marker "runtime.sqlite3" "sqlite3" -lsqlite3
append_libs_from_marker "runtime.pq" "libpq" -lpq
append_libs_from_marker "runtime.z" "zlib" -lz
append_libs_from_marker "runtime.zstd" "libzstd" -lzstd

"${CC[@]}" -O2 ${LTO_FLAG:+$LTO_FLAG} "$LLVM_IR" "$RUNTIME" -lm -lpthread "${EXTRA_LIBS[@]}" -o "$OUTPUT_BIN"
