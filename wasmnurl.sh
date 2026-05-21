#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  wasmnurl.sh — compile a .nu file to a native executable, but
#  use the *wasm-built* nurlc (nurlc.wasm) running under wasmtime
#  instead of the native nurlc binary. Stage 2 (LLVM IR -> binary)
#  is identical to nurl.sh.
#
#  Usage:  ./wasmnurl.sh [flags] <file.nu> [output_name]
#
#  Flags (same subset as nurl.sh):
#    --emit-ir | --emit=ir     Stop after stage 1, leave only the .ll
#    --emit-asm | --emit=asm   Emit .s (native assembly), skip link
#    -O0 | -O1 | -O2 | -O3     Clang optimisation level (default -O2)
#    -g | --debug              Pass -g to clang
#
#  Examples:
#    ./wasmnurl.sh examples/showcase.nu
#    ./wasmnurl.sh examples/showcase.nu showcase
#    ./wasmnurl.sh --emit-ir examples/hello.nu
#
#  Requires:
#    - wasmtime in PATH (or $WASMTIME)
#    - nurlc.wasm next to this script (or $NURLC_WASM)
#    - stdlib/runtime.o (build via `zig build bootstrap`)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Locate wasmtime ───────────────────────────────────────────
WASMTIME="${WASMTIME:-}"
if [[ -z "$WASMTIME" ]]; then
    if command -v wasmtime &>/dev/null; then
        WASMTIME="wasmtime"
    elif [[ -x "$HOME/.wasmtime/bin/wasmtime" ]]; then
        WASMTIME="$HOME/.wasmtime/bin/wasmtime"
    else
        echo "ERROR: wasmtime not found in PATH or ~/.wasmtime/bin." >&2
        echo "       Install: curl https://wasmtime.dev/install.sh -sSf | bash" >&2
        exit 1
    fi
fi

# ── Locate nurlc.wasm ─────────────────────────────────────────
NURLC_WASM="${NURLC_WASM:-$SCRIPT_DIR/nurlc.wasm}"
if [[ ! -f "$NURLC_WASM" ]]; then
    # Fallback: build/nurlc.wasm (in case build.sh starts emitting it there)
    if [[ -f "$SCRIPT_DIR/build/nurlc.wasm" ]]; then
        NURLC_WASM="$SCRIPT_DIR/build/nurlc.wasm"
    else
        echo "ERROR: nurlc.wasm not found at $NURLC_WASM" >&2
        echo "       Build it via the API's POST /build_wasm with compiler/nurlc.nu" >&2
        echo "       and drop the resulting .wasm next to this script." >&2
        exit 1
    fi
fi

# ── Locate runtime.o ──────────────────────────────────────────
RUNTIME="$SCRIPT_DIR/stdlib/runtime.o"
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: stdlib/runtime.o not found at $RUNTIME" >&2
    echo "       Run: zig build bootstrap" >&2
    exit 1
fi

# ── Parse arguments (mirrors nurl.sh) ─────────────────────────
EMIT_IR=0
EMIT_ASM=0
DEBUG_INFO=0
CLI_OPT=""

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --emit-ir|--emit=ir)   EMIT_IR=1;    shift ;;
        --emit-asm|--emit=asm) EMIT_ASM=1;   shift ;;
        -g|--debug)            DEBUG_INFO=1; shift ;;
        -O0|-O1|-O2|-O3)       CLI_OPT="$1"; shift ;;
        *) break ;;
    esac
done

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [flags] <file.nu> [output_name]" >&2
    exit 1
fi

SRCFILE="$1"
if [[ ! -f "$SRCFILE" ]]; then
    echo "ERROR: Source file not found: $SRCFILE" >&2
    exit 1
fi

if [[ $# -ge 2 ]]; then
    OUTBASE="$2"
else
    OUTBASE="${SRCFILE%.nu}"
fi

LLFILE="${OUTBASE}.ll"
SFILE="${OUTBASE}.s"

# ── Stage 1: .nu → LLVM IR via nurlc.wasm ─────────────────────
# wasmtime sandboxes the filesystem; expose the cwd (so relative
# paths like examples/foo.nu work) and the directory containing
# the source file (for absolute paths or paths outside cwd).
SRC_DIR="$(cd "$(dirname "$SRCFILE")" && pwd)"

WASMTIME_DIRS=(--dir=.)
# Also expose the source file's parent directory if it's outside cwd.
case "$SRC_DIR" in
    "$PWD"|"$PWD"/*) ;;
    *) WASMTIME_DIRS+=(--dir="$SRC_DIR") ;;
esac

if [[ $EMIT_IR -eq 1 ]]; then
    echo "[1/1] $SRCFILE → $LLFILE  (via nurlc.wasm)"
else
    echo "[1/2] $SRCFILE → $LLFILE  (via nurlc.wasm)"
fi

"$WASMTIME" run "${WASMTIME_DIRS[@]}" "$NURLC_WASM" "$SRCFILE" > "$LLFILE"

if [[ $EMIT_IR -eq 1 ]]; then
    echo ""
    echo "Done: $LLFILE"
    exit 0
fi

# ── Stage 2: LLVM IR → native binary (identical to nurl.sh) ──
if [[ -n "$CLI_OPT" ]]; then
    OPT="$CLI_OPT"
else
    OPT="${NURL_OPT:--O2}"
fi

DEBUG_FLAGS=()
if [[ $DEBUG_INFO -eq 1 ]]; then
    DEBUG_FLAGS=(-g)
fi

if [[ $EMIT_ASM -eq 1 ]]; then
    echo "[2/2] $LLFILE → $SFILE  ($OPT${DEBUG_FLAGS[*]:+ ${DEBUG_FLAGS[*]}} -S)"
    clang $OPT "${DEBUG_FLAGS[@]}" -S "$LLFILE" -o "$SFILE"
    echo ""
    echo "Done: $SFILE"
    exit 0
fi

EXTRA_OBJS=()
EXTRA_LIBS=()
if grep -qE '@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\b' "$LLFILE"; then
    CANVAS_O="$SCRIPT_DIR/stdlib/canvas.o"
    if [[ ! -f "$CANVAS_O" ]]; then
        echo "ERROR: program uses canvas FFI but $CANVAS_O is missing." >&2
        echo "       Run zig build bootstrap first." >&2
        exit 1
    fi
    EXTRA_OBJS+=("$CANVAS_O")
    if [[ -f "$SCRIPT_DIR/stdlib/canvas.sdl2" ]]; then
        EXTRA_LIBS+=("-lSDL2")
    else
        echo "[info] canvas.o is a stub build (no SDL2 at build time)." >&2
    fi
fi

if [[ -f "$SCRIPT_DIR/stdlib/runtime.curl" ]]; then
    if pkg-config --exists libcurl 2>/dev/null; then
        # shellcheck disable=SC2046
        EXTRA_LIBS+=( $(pkg-config --libs libcurl) )
    else
        EXTRA_LIBS+=( -lcurl )
    fi
fi

echo "[2/2] $LLFILE → $OUTBASE  ($OPT${DEBUG_FLAGS[*]:+ ${DEBUG_FLAGS[*]}}${EXTRA_LIBS[*]:+ ${EXTRA_LIBS[*]}})"
clang $OPT "${DEBUG_FLAGS[@]}" "$LLFILE" "$RUNTIME" "${EXTRA_OBJS[@]}" -o "$OUTBASE" -lm -lpthread "${EXTRA_LIBS[@]}"
echo ""
echo "Done: $OUTBASE"
