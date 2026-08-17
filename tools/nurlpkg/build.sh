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

# The link flags build.sh resolved, when this runs under it. `--as-needed`
# is GNU ld / lld spelling and Apple's ld64 errors on it; $OPAQUE_FLAGS
# carries whatever this clang needs to parse nurlc's opaque-pointer IR.
# Standalone, fall back the way build.sh does.
OPAQUE_FLAGS="${OPAQUE_FLAGS-}"
if [ -z "${AS_NEEDED+set}" ]; then
    AS_NEEDED="-Wl,--as-needed"
    case "$(uname -s)" in Darwin) AS_NEEDED="-Wl,-dead_strip_dylibs" ;; esac
fi
if ! command -v "$CLANG" >/dev/null 2>&1; then
    echo "ERROR: clang not on PATH (set CLANG=/path/to/clang to override)." >&2
    exit 1
fi

mkdir -p "$ROOT_DIR/build"

echo "[1/2] $SRC → build/nurlpkg.ll"
"$NURLC" "$SRC" > "$ROOT_DIR/build/nurlpkg.ll"

# Dependency policy for the shipped `nurlpkg` (the whole point of this
# rewrite): the binary's ONLY dynamic dependency must be libc, so it can
# never be wedged on a fresh box by a missing shared library (the original
# bug: a stray libpq.so.5 NEEDED entry stopped `nurlpkg install` dead on a
# machine with no Postgres client).
#
# Two mechanisms get us there:
#
#   1. nurlpkg does NOT link libcurl / OpenSSL / sqlite / libpq at all. It
#      reaches the registry through the system `curl` BINARY
#      (stdlib/ext/http_cli.nu) — already required by the install
#      one-liner — and its only crypto is pure-NURL SHA-256. Those backends
#      still live in the monolithic runtime.o, but nurlpkg references none
#      of their symbols, so LTO drops the code; we simply never name the
#      libs here.
#
#   2. Its compression (gzip/zstd of package tarballs) is pure NURL, so
#      linked STATICALLY when a static archive is available, so they leave
#      no DT_NEEDED behind. We fall back to dynamic only if the .a is
#      absent. `-Wl,--as-needed` on the link line then strips any -lm /
#      -lpthread that turns out unreferenced.
EXTRA_LIBS=()

# Append a compression lib, preferring its static archive (.a) so the
# shipped binary keeps no runtime .so dependency. $1 pkg-config name,
# $2 bare lib name (zlib→z), $3 archive file name (libz.a).
add_static_lib() {
    local pcname="$1" lname="$2" aname="$3" apath
    apath="$("$CLANG" -print-file-name="$aname" 2>/dev/null)"
    if [[ -n "$apath" && "$apath" != "$aname" && -f "$apath" ]]; then
        # An explicit path to a .a links it statically regardless of -B mode.
        EXTRA_LIBS+=( "$apath" )
    elif pkg-config --exists "$pcname" 2>/dev/null; then
        # shellcheck disable=SC2207
        EXTRA_LIBS+=( $(pkg-config --libs "$pcname") )
    else
        EXTRA_LIBS+=( "-l$lname" )
    fi
}
if [[ -f "$ROOT_DIR/stdlib/runtime.z" ]];    then add_static_lib zlib    z    libz.a;    fi

echo "[2/2] build/nurlpkg.ll → build/nurlpkg"
# shellcheck disable=SC2086
"$CLANG" -O2 -flto $OPAQUE_FLAGS $AS_NEEDED "$ROOT_DIR/build/nurlpkg.ll" "$RUNTIME" -lm -lpthread "${EXTRA_LIBS[@]}" -o "$ROOT_DIR/build/nurlpkg"

echo ""
echo "Done: $ROOT_DIR/build/nurlpkg"
