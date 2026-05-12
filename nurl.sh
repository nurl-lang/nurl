#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  nurl.sh — compile a .nu file to a native executable
#
#  Usage:  ./nurl.sh [flags] <file.nu> [output_name]
#
#  Flags (all must come before the source file):
#    --emit-ir | --emit=ir     Stop after stage 1, leave only the .ll
#    --emit-asm | --emit=asm   Emit .s (native assembly), skip link
#    -O0 | -O1 | -O2 | -O3     Clang optimisation level (default -O2)
#    -g | --debug              Pass -g to clang (DWARF line tables)
#
#  Examples:
#    ./nurl.sh hello.nu             → ./hello
#    ./nurl.sh src/myprog.nu prog   → ./prog
#    ./nurl.sh --emit-ir hello.nu   → ./hello.ll  (skip link)
#    ./nurl.sh --emit-asm hello.nu  → ./hello.s   (skip link)
#    ./nurl.sh -O0 -g hello.nu      → ./hello with debug info, no opt
#
#  Requires nurlc and stdlib/runtime.o in the same directory
#  as this script (or nurlc in PATH).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Locate nurlc ─────────────────────────────────────────────
NURLC="$SCRIPT_DIR/build/nurlc"
if [[ ! -x "$NURLC" ]]; then
    # Fallback to old location for backwards compatibility
    NURLC="$SCRIPT_DIR/nurlc"
    if [[ ! -x "$NURLC" ]]; then
        if command -v nurlc &>/dev/null; then
            NURLC="nurlc"
        else
            echo "ERROR: nurlc not found in build/, next to this script, or in PATH" >&2
            echo "       Run: ./build.sh to build the compiler" >&2
            exit 1
        fi
    fi
fi

# ── Locate runtime.o ─────────────────────────────────────────
RUNTIME="$SCRIPT_DIR/stdlib/runtime.o"
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: stdlib/runtime.o not found at $RUNTIME" >&2
    echo "       Run: clang -c stdlib/runtime.c -o stdlib/runtime.o" >&2
    exit 1
fi

# ── Parse arguments ───────────────────────────────────────────
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
    echo "" >&2
    echo "  Flags: --emit-ir | --emit-asm | -O0..-O3 | -g | --debug" >&2
    echo "" >&2
    echo "  Compiles a NURL source file to a native binary." >&2
    echo "  The intermediate .ll file is kept alongside the output." >&2
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

# ── Step 1: .nu → LLVM IR ────────────────────────────────────
if [[ $EMIT_IR -eq 1 ]]; then
    echo "[1/1] $SRCFILE → $LLFILE"
else
    echo "[1/2] $SRCFILE → $LLFILE"
fi
"$NURLC" "$SRCFILE" > "$LLFILE"

if [[ $EMIT_IR -eq 1 ]]; then
    echo ""
    echo "Done: $LLFILE"
    exit 0
fi

# ── Step 2: LLVM IR → native binary (or .s with --emit-asm) ──
# nurlc emits `alloca` inside loop bodies (not entry blocks), so at -O0
# each loop iteration leaks a stack slot and long-running programs
# segfault on the default 8 MB stack. -O2 runs mem2reg which hoists
# them out; override with NURL_OPT=-O0 or the -O0 CLI flag when debugging.
if [[ -n "$CLI_OPT" ]]; then
    OPT="$CLI_OPT"
else
    OPT="${NURL_OPT:--O2}"
fi

# Debug flag passthrough. Without `!dbg` metadata in the IR, `-g` yields
# only crude line info from the inlined .ll filename; still useful in
# debuggers for frame isolation and symbol demangling.
DEBUG_FLAGS=()
if [[ $DEBUG_INFO -eq 1 ]]; then
    DEBUG_FLAGS=(-g)
fi

# --emit-asm: stop after clang -S, skip linking (no runtime needed for .s).
if [[ $EMIT_ASM -eq 1 ]]; then
    echo "[2/2] $LLFILE → $SFILE  ($OPT${DEBUG_FLAGS[*]:+ ${DEBUG_FLAGS[*]}} -S)"
    clang $OPT "${DEBUG_FLAGS[@]}" -S "$LLFILE" -o "$SFILE"
    echo ""
    echo "Done: $SFILE"
    exit 0
fi

# Auto-link the canvas back-end and SDL2 if the program calls into the
# canvas_* FFI. Otherwise a plain `clang runtime.o` is enough.
EXTRA_OBJS=()
EXTRA_LIBS=()
if grep -qE '@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\b' "$LLFILE"; then
    CANVAS_O="$SCRIPT_DIR/stdlib/canvas.o"
    if [[ ! -f "$CANVAS_O" ]]; then
        echo "ERROR: program uses canvas FFI but $CANVAS_O is missing." >&2
        echo "       Run ./build.sh to build the NURL stdlib first." >&2
        exit 1
    fi
    EXTRA_OBJS+=("$CANVAS_O")
    # -lSDL2 is added only when canvas.o was compiled with the real SDL2
    # back-end (build.sh drops a marker file in that case). On a stub
    # build the exe links fine without SDL2, but any canvas_* call will
    # abort at runtime with a clear diagnostic.
    if [[ -f "$SCRIPT_DIR/stdlib/canvas.sdl2" ]]; then
        EXTRA_LIBS+=("-lSDL2")
    else
        echo "[info] canvas.o is a stub build (no SDL2 at build time)." >&2
        echo "       Program will compile and link, but any canvas_* call will" >&2
        echo "       abort at runtime with a diagnostic." >&2
    fi
fi

# Auto-link libcurl when the runtime was built with HTTP support
# (build.sh drops a stdlib/runtime.curl marker). Programs that don't
# import stdlib/ext/http.nu still link cleanly without it.
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
