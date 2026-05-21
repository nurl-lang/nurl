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
            echo "       Run: zig build bootstrap" >&2
            exit 1
        fi
    fi
fi

# ── Locate runtime.o ─────────────────────────────────────────
RUNTIME="$SCRIPT_DIR/stdlib/runtime.o"
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: stdlib/runtime.o not found at $RUNTIME" >&2
    echo "       Run: zig build bootstrap" >&2
    exit 1
fi

# ── Locate the C toolchain driver ────────────────────────────
# NURL_CC selects the compiler+linker driver. Defaults to clang; set
# NURL_CC="zig cc" to compile and link through Zig's bundled toolchain
# (must match the driver build.sh used for stdlib/runtime.o so the LTO
# bitcode versions agree). Multi-word values (e.g. "zig cc") supported.
read -r -a CC <<< "${NURL_CC:-clang}"

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
# When --debug is on, also forward --g to nurlc so it emits DWARF
# !DICompileUnit / !DISubprogram / !DILocation metadata that clang's
# -g pulls into the final .debug_info section.
NURLC_ARGS=()
if [[ $DEBUG_INFO -eq 1 ]]; then
    NURLC_ARGS+=(--g)
fi
# ${arr[@]+...} guard: expanding an empty array under `set -u` is an
# "unbound variable" error on bash 3.2 (macOS's stock shell).
"$NURLC" ${NURLC_ARGS[@]+"${NURLC_ARGS[@]}"} "$SRCFILE" > "$LLFILE"

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
    # -g: DWARF debug info (nurlc --g emitted the metadata; clang
    #   resolves it into .debug_info on a non-LTO link — see below).
    # -rdynamic: export dynamic symbols so libc's backtrace_symbols
    #   used by nurl_panic can render function names (vs. raw addrs).
    DEBUG_FLAGS=(-g -rdynamic)
fi

# --emit-asm: stop after clang -S, skip linking (no runtime needed for .s).
if [[ $EMIT_ASM -eq 1 ]]; then
    echo "[2/2] $LLFILE → $SFILE  ($OPT${DEBUG_FLAGS[*]:+ ${DEBUG_FLAGS[*]}} -S)"
    "${CC[@]}" $OPT ${DEBUG_FLAGS[@]+"${DEBUG_FLAGS[@]}"} -S "$LLFILE" -o "$SFILE"
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
        echo "       Run zig build bootstrap first." >&2
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

# In --debug mode, drop -flto: the LTO link pipeline strips DWARF
# debug info from .ll input when the matching runtime.o bitcode has
# no DI counterpart (current build.sh compiles runtime.o without -g).
# A side-by-side non-LTO build of runtime.c restores .debug_info in
# the final binary; the LTO inline win for stdlib FFI is gone, but
# that's the right trade for a debug build.
# build.sh drops stdlib/runtime.nolto when it built runtime.o as a plain
# native object (e.g. `zig cc` on macOS, which can't LTO) instead of LLVM
# bitcode. In that case the link must NOT pass -flto, or the driver may
# reject it / find no bitcode to inline.
if [[ -f "$SCRIPT_DIR/stdlib/runtime.nolto" ]]; then
    LTO_FLAG=""
else
    LTO_FLAG="-flto"
fi
RUNTIME_TO_LINK="$RUNTIME"
if [[ $DEBUG_INFO -eq 1 ]]; then
    LTO_FLAG=""
    DBG_RUNTIME="$SCRIPT_DIR/stdlib/runtime_debug.o"
    if [[ ! -f "$DBG_RUNTIME" || "$SCRIPT_DIR/stdlib/runtime.c" -nt "$DBG_RUNTIME" ]]; then
        echo "[runtime-debug] rebuilding stdlib/runtime_debug.o (non-LTO, with -g)"
        CFLAGS_DBG="-O0 -g"
        for sentinel_flag in NURL_HAVE_LIBCURL:libcurl NURL_HAVE_OPENSSL:openssl NURL_HAVE_SQLITE3:sqlite3 NURL_HAVE_ZLIB:zlib; do
            d="${sentinel_flag%%:*}"; p="${sentinel_flag##*:}"
            if pkg-config --exists "$p" 2>/dev/null; then
                CFLAGS_DBG="$CFLAGS_DBG -D$d $(pkg-config --cflags "$p")"
            fi
        done
        # shellcheck disable=SC2086
        "${CC[@]}" $CFLAGS_DBG -c "$SCRIPT_DIR/stdlib/runtime.c" -o "$DBG_RUNTIME"
    fi
    RUNTIME_TO_LINK="$DBG_RUNTIME"
fi

LINK_HELPER="$SCRIPT_DIR/build/nurl-build"
if [[ ! -x "$LINK_HELPER" ]]; then
    ZIG_BIN="${NURL_ZIG:-zig}"
    if command -v "$ZIG_BIN" >/dev/null 2>&1 && [[ -f "$SCRIPT_DIR/build.zig" ]]; then
        echo "[nurl.sh] build/nurl-build missing — bootstrapping..." >&2
        (
            cd "$SCRIPT_DIR"
            "$ZIG_BIN" build nurl-build
        )
    fi
fi
if [[ ! -x "$LINK_HELPER" ]]; then
    LINK_HELPER="$SCRIPT_DIR/tools/nurl-build/run.sh"
fi
if [[ ! -x "$LINK_HELPER" ]]; then
    echo "ERROR: nurl-build helper not found at $SCRIPT_DIR/build/nurl-build" >&2
    echo "       Run: zig build nurl-build" >&2
    exit 1
fi

echo "[2/2] $LLFILE → $OUTBASE  ($OPT${LTO_FLAG:+ $LTO_FLAG}${DEBUG_FLAGS[*]:+ ${DEBUG_FLAGS[*]}}${EXTRA_LIBS[*]:+ ${EXTRA_LIBS[*]}})"
LINK_ARGS=( --opt "$OPT" )
if [[ $DEBUG_INFO -eq 1 ]]; then
    LINK_ARGS+=( --no-lto --runtime "$RUNTIME_TO_LINK" )
    for flag in "${DEBUG_FLAGS[@]}"; do
        LINK_ARGS+=( --flag "$flag" )
    done
fi
if [[ ${#EXTRA_OBJS[@]} -gt 0 ]]; then
    for obj in "${EXTRA_OBJS[@]}"; do
        LINK_ARGS+=( --extra-obj "$obj" )
    done
fi
if [[ ${#EXTRA_LIBS[@]} -gt 0 ]]; then
    for lib in "${EXTRA_LIBS[@]}"; do
        LINK_ARGS+=( --extra-lib "$lib" )
    done
fi
"$LINK_HELPER" "${LINK_ARGS[@]}" "$SCRIPT_DIR" "$LLFILE" "$OUTBASE"

echo ""
echo "Done: $OUTBASE"
