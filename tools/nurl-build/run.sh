#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Shared link helper for repo-local NURL tooling binaries.
# Prefers the compiled `build/nurl-build` helper; otherwise it
# bootstraps/runs the Zig implementation, and finally falls back to
# the legacy shell policy when Zig itself is unavailable.

set -euo pipefail

ORIG_ARGS=("$@")

OPT="-O2"
RUNTIME=""
FORCE_NO_LTO=0
EXTRA_FLAGS=()
EXTRA_OBJS=()
EXTRA_LIBS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --opt)
            OPT="${2:?missing value for --opt}"
            shift 2
            ;;
        --runtime)
            RUNTIME="${2:?missing value for --runtime}"
            shift 2
            ;;
        --no-lto)
            FORCE_NO_LTO=1
            shift
            ;;
        --flag)
            EXTRA_FLAGS+=("${2:?missing value for --flag}")
            shift 2
            ;;
        --extra-obj)
            EXTRA_OBJS+=("${2:?missing value for --extra-obj}")
            shift 2
            ;;
        --extra-lib)
            EXTRA_LIBS+=("${2:?missing value for --extra-lib}")
            shift 2
            ;;
        --*)
            echo "unknown option: $1" >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -ne 3 ]]; then
    echo "usage: $0 [--opt <flag>] [--runtime <path>] [--no-lto] [--flag <arg>] [--extra-obj <path>] [--extra-lib <arg>] <repo-root> <llvm-ir> <output-bin>" >&2
    exit 2
fi

ROOT_DIR="$1"
LLVM_IR="$2"
OUTPUT_BIN="$3"
if [[ -z "$RUNTIME" ]]; then
    RUNTIME="$ROOT_DIR/stdlib/runtime.o"
fi

if [[ ! -f "$LLVM_IR" ]]; then
    echo "ERROR: LLVM IR not found at $LLVM_IR" >&2
    exit 1
fi
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: runtime.o not found at $RUNTIME" >&2
    echo "       Run zig build bootstrap first to compile the runtime." >&2
    exit 1
fi

ZIG_BIN="${NURL_ZIG:-zig}"
HELPER_BIN="${NURL_BUILD_BIN:-$ROOT_DIR/build/nurl-build}"
if [[ -x "$HELPER_BIN" ]]; then
    exec "$HELPER_BIN" "${ORIG_ARGS[@]}"
fi

if command -v "$ZIG_BIN" >/dev/null 2>&1; then
    if [[ -f "$ROOT_DIR/build.zig" ]]; then
        if (
            cd "$ROOT_DIR"
            "$ZIG_BIN" build nurl-build
        ); then
            if [[ -x "$HELPER_BIN" ]]; then
                exec "$HELPER_BIN" "${ORIG_ARGS[@]}"
            fi
        fi
    fi
    mkdir -p "$ROOT_DIR/.zig-cache" "$ROOT_DIR/.zig-cache-global"
    HELPER_ARGS=()
    [[ "$OPT" != "-O2" ]] && HELPER_ARGS+=(--opt "$OPT")
    [[ -n "$RUNTIME" && "$RUNTIME" != "$ROOT_DIR/stdlib/runtime.o" ]] && HELPER_ARGS+=(--runtime "$RUNTIME")
    [[ $FORCE_NO_LTO -eq 1 ]] && HELPER_ARGS+=(--no-lto)
    if [[ ${#EXTRA_FLAGS[@]} -gt 0 ]]; then
        for flag in "${EXTRA_FLAGS[@]}"; do
            HELPER_ARGS+=(--flag "$flag")
        done
    fi
    if [[ ${#EXTRA_OBJS[@]} -gt 0 ]]; then
        for extra_obj in "${EXTRA_OBJS[@]}"; do
            HELPER_ARGS+=(--extra-obj "$extra_obj")
        done
    fi
    if [[ ${#EXTRA_LIBS[@]} -gt 0 ]]; then
        for extra_lib in "${EXTRA_LIBS[@]}"; do
            HELPER_ARGS+=(--extra-lib "$extra_lib")
        done
    fi
    exec env \
        ZIG_LOCAL_CACHE_DIR="$ROOT_DIR/.zig-cache" \
        ZIG_GLOBAL_CACHE_DIR="$ROOT_DIR/.zig-cache-global" \
        "$ZIG_BIN" run "$ROOT_DIR/tools/nurl-build/main.zig" -- ${HELPER_ARGS[@]+"${HELPER_ARGS[@]}"} "$ROOT_DIR" "$LLVM_IR" "$OUTPUT_BIN"
fi

read -r -a CC <<< "${NURL_CC:-${CLANG:-clang}}"
if ! command -v "${CC[0]}" >/dev/null 2>&1; then
    echo "ERROR: C driver '${CC[*]}' not found." >&2
    exit 1
fi

LTO_FLAG="-flto"
if [[ $FORCE_NO_LTO -eq 1 || -f "$ROOT_DIR/stdlib/runtime.nolto" ]]; then
    LTO_FLAG=""
fi

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

if [[ ${#EXTRA_OBJS[@]} -gt 0 ]]; then
    for extra_obj in "${EXTRA_OBJS[@]}"; do
        if [[ ! -f "$extra_obj" ]]; then
            echo "ERROR: extra object not found at $extra_obj" >&2
            exit 1
        fi
    done
fi

"${CC[@]}" "$OPT" ${LTO_FLAG:+$LTO_FLAG} ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} "$LLVM_IR" "$RUNTIME" ${EXTRA_OBJS[@]+"${EXTRA_OBJS[@]}"} -o "$OUTPUT_BIN" -lm -lpthread ${EXTRA_LIBS[@]+"${EXTRA_LIBS[@]}"}
