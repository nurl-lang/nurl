#!/bin/sh
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
#  Environment:
#    NURL_OPT=-O0..-O3   Override default -O2 when no CLI flag given
#    NURL_SAN=1          Link with AddressSanitizer + UndefinedBehaviorSanitizer.
#                        Auto-builds a side-by-side stdlib/runtime_san.o (non-LTO,
#                        same -fsanitize flags). LTO is dropped because clang's
#                        LTO + sanitizers combination produces opaque link-time
#                        diagnostics on NURL's cross-module function-pointer
#                        patterns. Set automatically by `./build.sh --san`.
#                        Combine with ASAN_OPTIONS / UBSAN_OPTIONS at runtime.
#
#  Examples:
#    ./nurl.sh hello.nu             → ./hello
#    ./nurl.sh src/myprog.nu prog   → ./prog
#    ./nurl.sh --emit-ir hello.nu   → ./hello.ll  (skip link)
#    ./nurl.sh --emit-asm hello.nu  → ./hello.s   (skip link)
#    ./nurl.sh -O0 -g hello.nu      → ./hello with debug info, no opt
#    NURL_SAN=1 ./nurl.sh hello.nu  → ./hello linked with ASan + UBSan
#
#  Requires nurlc and stdlib/runtime.o in the same directory
#  as this script (or nurlc in PATH).
#
#  POSIX sh — no bashisms. The installed toolchain must run on a stock
#  FreeBSD / Alpine / busybox box where /bin/sh is not bash (the shipped
#  binaries depend on libc only; the wrapper must not reintroduce a bash
#  dependency). Compiler/flag "arrays" are modelled as a cc_run() function
#  plus space-separated flag strings expanded UNQUOTED at the link line —
#  safe here because every flag token is whitespace-free.
# ============================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Locate nurlc ─────────────────────────────────────────────
NURLC="$SCRIPT_DIR/build/nurlc"
if [ ! -x "$NURLC" ]; then
    # Fallback to old location for backwards compatibility
    NURLC="$SCRIPT_DIR/nurlc"
    if [ ! -x "$NURLC" ]; then
        if command -v nurlc >/dev/null 2>&1; then
            NURLC="nurlc"
        else
            echo "ERROR: nurlc not found in build/, next to this script, or in PATH" >&2
            echo "       Run: ./build.sh to build the compiler" >&2
            exit 1
        fi
    fi
fi

# ── --version ────────────────────────────────────────────────
# The version is baked into nurlc (runtime.o), so this needs no stdlib/env.
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    exec "$NURLC" --version
fi

# ── Locate runtime.o ─────────────────────────────────────────
RUNTIME="$SCRIPT_DIR/stdlib/runtime.o"
if [ ! -f "$RUNTIME" ]; then
    echo "ERROR: stdlib/runtime.o not found at $RUNTIME" >&2
    echo "       Run: clang -c stdlib/runtime.c -o stdlib/runtime.o" >&2
    exit 1
fi

# ── Parse arguments ───────────────────────────────────────────
EMIT_IR=0
EMIT_ASM=0
DEBUG_INFO=0
CLI_OPT=""

while [ $# -gt 0 ]; do
    case "${1:-}" in
        --emit-ir|--emit=ir)   EMIT_IR=1;    shift ;;
        --emit-asm|--emit=asm) EMIT_ASM=1;   shift ;;
        -g|--debug)            DEBUG_INFO=1; shift ;;
        -O0|-O1|-O2|-O3)       CLI_OPT="$1"; shift ;;
        *) break ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Usage: $0 [flags] <file.nu> [output_name]" >&2
    echo "" >&2
    echo "  Flags: --emit-ir | --emit-asm | -O0..-O3 | -g | --debug" >&2
    echo "" >&2
    echo "  Compiles a NURL source file to a native binary." >&2
    echo "  The intermediate .ll file is kept alongside the output." >&2
    exit 1
fi

SRCFILE="$1"
if [ ! -f "$SRCFILE" ]; then
    echo "ERROR: Source file not found: $SRCFILE" >&2
    exit 1
fi

if [ $# -ge 2 ]; then
    OUTBASE="$2"
else
    OUTBASE="${SRCFILE%.nu}"
fi

LLFILE="${OUTBASE}.ll"
SFILE="${OUTBASE}.s"

# ── Step 1: .nu → LLVM IR ────────────────────────────────────
if [ $EMIT_IR -eq 1 ]; then
    echo "[1/1] $SRCFILE → $LLFILE"
else
    echo "[1/2] $SRCFILE → $LLFILE"
fi
# When --debug is on, also forward --g to nurlc so it emits DWARF
# !DICompileUnit / !DISubprogram / !DILocation metadata that clang's
# -g pulls into the final .debug_info section.
NURLC_G=""
if [ $DEBUG_INFO -eq 1 ]; then
    NURLC_G="--g"
fi
# shellcheck disable=SC2086
"$NURLC" $NURLC_G "$SRCFILE" > "$LLFILE"

if [ $EMIT_IR -eq 1 ]; then
    echo ""
    echo "Done: $LLFILE"
    exit 0
fi

# ── Step 2: LLVM IR → native binary (or .s with --emit-asm) ──
# nurlc emits `alloca` inside loop bodies (not entry blocks), so at -O0
# each loop iteration leaks a stack slot and long-running programs
# segfault on the default 8 MB stack. -O2 runs mem2reg which hoists
# them out; override with NURL_OPT=-O0 or the -O0 CLI flag when debugging.
if [ -n "$CLI_OPT" ]; then
    OPT="$CLI_OPT"
else
    OPT="${NURL_OPT:--O2}"
fi

# Resolve an LLVM C compiler to lower nurlc's LLVM IR (.ll) into a native
# binary. This step *requires* clang (or another LLVM-based `cc`): nurlc
# emits LLVM IR, which gcc/cc cannot consume. Honour an explicit $CLANG,
# then probe `clang` and a few versioned names, and otherwise fail with
# install guidance instead of a raw "clang: command not found".
resolve_clang() {
    if [ -n "${CLANG:-}" ] && command -v "$CLANG" >/dev/null 2>&1; then
        return 0
    fi
    for c in clang clang-20 clang-19 clang-18 clang-17 clang-16 clang-15 clang-14 cc; do
        # `cc` is accepted only if it is actually clang (it can be gcc).
        if command -v "$c" >/dev/null 2>&1; then
            if [ "$c" = cc ] && ! "$c" --version 2>/dev/null | grep -qi clang; then
                continue
            fi
            CLANG="$c"
            return 0
        fi
    done
    {
        echo "ERROR: NURL needs an LLVM C compiler (clang) to build a program."
        echo "       nurlc emits LLVM IR, which clang lowers to a native binary;"
        echo "       gcc/cc cannot do this. Install clang and re-run:"
        echo "         Debian/Ubuntu:  sudo apt-get install -y clang"
        echo "         Fedora/RHEL:    sudo dnf install -y clang"
        echo "         Alpine:         sudo apk add clang"
        echo "         Arch:           sudo pacman -S clang"
        echo "         FreeBSD:        sudo pkg install -y llvm   # clang is in base on 14+"
        echo "         macOS:          xcode-select --install   # or: brew install llvm"
        echo "       Or set CLANG=/path/to/clang if it is installed under another name."
    } >&2
    exit 1
}

# ── Pick the compiler: bundled zig (preferred) or system clang ──────────
# A bundled `zig cc` carries its own modern LLVM (so nurlc's opaque-pointer
# IR just parses), its own lld linker, and libc headers — so building needs
# no system clang at all and is immune to the system's LLVM version (the
# two walls a fresh distro hit: `clang: not found`, and clang 14 rejecting
# opaque pointers / unable to read the shipped bitcode). Point at it with
# $NURL_ZIG, or ship it at <prefix>/zig/zig. Fall back to a system clang.
#
# `cc_run` is the POSIX stand-in for the bash `CC=(...)` array: it invokes
# either `zig cc` (two words) or a single clang, forwarding "$@" intact —
# whitespace-safe regardless of the prefix path.
ZIG_BIN="${NURL_ZIG:-$SCRIPT_DIR/zig/zig}"
OPAQUE_FLAGS=""
if [ -x "$ZIG_BIN" ]; then
    cc_run() { "$ZIG_BIN" cc "$@"; }
else
    resolve_clang
    cc_run() { "$CLANG" "$@"; }
    # nurlc emits LLVM IR with opaque pointers (`ptr`) — the default since
    # LLVM 15, which is NURL's minimum supported clang. Older clangs (13/14
    # behind `-opaque-pointers`) are no longer supported. (zig's bundled
    # LLVM never needs this.)
    CLANG_MAJOR="$("$CLANG" --version 2>/dev/null | sed -nE 's/.*version ([0-9]+).*/\1/p' | head -1)"
    if [ -n "$CLANG_MAJOR" ] && [ "$CLANG_MAJOR" -lt 15 ]; then
        {
            echo "ERROR: clang $CLANG_MAJOR is too old to build NURL programs."
            echo "       nurlc emits LLVM IR with opaque pointers (needs clang/LLVM 15+)."
            echo "       Install a newer clang (e.g. clang-15) and set CLANG=clang-15,"
            echo "       or use the bundled zig backend (set NURL_ZIG=/path/to/zig)."
        } >&2
        exit 1
    fi
fi

# Debug flag passthrough. Without `!dbg` metadata in the IR, `-g` yields
# only crude line info from the inlined .ll filename; still useful in
# debuggers for frame isolation and symbol demangling.
DEBUG_FLAGS=""
if [ $DEBUG_INFO -eq 1 ]; then
    # -g: DWARF debug info (nurlc --g emitted the metadata; clang
    #   resolves it into .debug_info on a non-LTO link — see below).
    # -rdynamic: export dynamic symbols so libc's backtrace_symbols
    #   used by nurl_panic can render function names (vs. raw addrs).
    DEBUG_FLAGS="-g -rdynamic"
fi

# --emit-asm: stop after clang -S, skip linking (no runtime needed for .s).
if [ $EMIT_ASM -eq 1 ]; then
    echo "[2/2] $LLFILE → $SFILE  ($OPT${DEBUG_FLAGS:+ $DEBUG_FLAGS} -S)"
    # shellcheck disable=SC2086
    cc_run $OPT $DEBUG_FLAGS $OPAQUE_FLAGS -S "$LLFILE" -o "$SFILE"
    echo ""
    echo "Done: $SFILE"
    exit 0
fi

# Auto-link the canvas back-end and SDL2 if the program calls into the
# canvas_* FFI. Otherwise a plain `clang runtime.o` is enough.
EXTRA_OBJS=""
EXTRA_LIBS=""

# Runtime TLS resolves OpenSSL at runtime via dlopen/dlsym, so runtime.o has
# no link-time libssl reference. dlopen/dlsym live in libdl on the glibc
# (< 2.34) floor the portable build targets — so on Linux we link -ldl
# (`--as-needed` drops it on newer glibc where they fold into libc, and when
# a program never touches TLS). FreeBSD/macOS keep dlopen in libc and ship no
# separate libdl, so -ldl is omitted there.
DL_LIB=""
case "$(uname -s)" in
    Linux) DL_LIB="-ldl" ;;
esac
if grep -qE '@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\b' "$LLFILE"; then
    CANVAS_O="$SCRIPT_DIR/stdlib/canvas.o"
    if [ ! -f "$CANVAS_O" ]; then
        echo "ERROR: program uses canvas FFI but $CANVAS_O is missing." >&2
        echo "       Run ./build.sh to build the NURL stdlib first." >&2
        exit 1
    fi
    EXTRA_OBJS="$EXTRA_OBJS $CANVAS_O"
    # -lSDL2 is added only when canvas.o was compiled with the real SDL2
    # back-end (build.sh drops a marker file in that case). On a stub
    # build the exe links fine without SDL2, but any canvas_* call will
    # abort at runtime with a clear diagnostic.
    if [ -f "$SCRIPT_DIR/stdlib/canvas.sdl2" ]; then
        EXTRA_LIBS="$EXTRA_LIBS -lSDL2"
    else
        echo "[info] canvas.o is a stub build (no SDL2 at build time)." >&2
        echo "       Program will compile and link, but any canvas_* call will" >&2
        echo "       abort at runtime with a diagnostic." >&2
    fi
fi

# Auto-link OpenSSL / sqlite3 / libpq / zstd — for each
# back-end the runtime was built with (runtime.<name> sentinel), but only
# if the library is actually AVAILABLE to the compiler on this box (probed
# with a tiny trial link). Rationale:
#   * Correctness: a program that uses a feature gets its lib. Detecting use
#     from the emitted IR is fragile — the back-end symbol may live in
#     runtime.o behind a wrapper the program calls (this is how an earlier
#     symbol-grep approach silently dropped `-lssl` and broke nurlapi's TLS
#     link). Probing availability instead is symbol-pattern-free.
#   * Leanness: under LTO + `-Wl,--as-needed`, a passed-but-unused library
#     is dropped from the final NEEDED set, so a feature-free program stays
#     at libc only even though every available lib was on the link line.
#   * Portability: a lib the box LACKS is simply not named, so a hello-world
#     links on a box without (say) the Postgres client — where an
#     unconditional `-lpq` used to fail with `cannot find -lpq`. A program
#     that truly needs an absent lib still fails, with a clear
#     undefined-symbol error.
__probe_c="$(mktemp "${TMPDIR:-/tmp}/nurl-probe.XXXXXX.c")"
__probe_o="$(mktemp "${TMPDIR:-/tmp}/nurl-probe.XXXXXX.out")"
printf 'int main(void){return 0;}\n' > "$__probe_c"
add_feature_lib() {
    # $1 sentinel basename, $2.. the link flags (e.g. -lssl -lcrypto).
    sentinel="$1"; shift
    [ -f "$SCRIPT_DIR/stdlib/$sentinel" ] || return 0
    # A FAILED probe (lib absent — common: the runtime .so.N is present but
    # the -dev `.so` linker symlink is not) means "don't link it". Use an
    # `if`, never `probe && add`: the latter makes this function return the
    # probe's non-zero exit, which under the caller's `set -e` aborts the
    # whole build at the first unavailable library. `return 0` keeps the
    # function total regardless.
    if cc_run "$__probe_c" "$@" -o "$__probe_o" >/dev/null 2>&1; then
        EXTRA_LIBS="$EXTRA_LIBS $*"
    fi
    return 0
}
add_feature_lib runtime.sqlite3 -lsqlite3
add_feature_lib runtime.pq      -lpq
add_feature_lib runtime.zstd    -lzstd
rm -f "$__probe_c" "$__probe_o"

# Auto-link libopus / ALSA when the program references their FFI symbols
# (pttvoice and any audio app). Linked only when actually used, so other
# programs don't grow a dependency. libopus ships no unversioned .so on
# Debian/Ubuntu, so link the soname directly.
if grep -qE '@opus_(encoder_create|encoder_destroy|encode|decoder_create|decoder_destroy|decode|strerror)\b' "$LLFILE"; then
    if pkg-config --exists opus 2>/dev/null; then
        EXTRA_LIBS="$EXTRA_LIBS $(pkg-config --libs opus)"
    elif [ -e /usr/lib/x86_64-linux-gnu/libopus.so ] || [ -e /usr/lib/libopus.so ]; then
        EXTRA_LIBS="$EXTRA_LIBS -lopus"
    else
        EXTRA_LIBS="$EXTRA_LIBS -l:libopus.so.0"
    fi
fi
if grep -qE '@snd_pcm_[A-Za-z_]+\b' "$LLFILE"; then
    if pkg-config --exists alsa 2>/dev/null; then
        EXTRA_LIBS="$EXTRA_LIBS $(pkg-config --libs alsa)"
    else
        EXTRA_LIBS="$EXTRA_LIBS -lasound"
    fi
fi

# In --debug mode, drop -flto: the LTO link pipeline strips DWARF
# debug info from .ll input when the matching runtime.o bitcode has
# no DI counterpart (current build.sh compiles runtime.o without -g).
# A side-by-side non-LTO build of runtime.c restores .debug_info in
# the final binary; the LTO inline win for stdlib FFI is gone, but
# that's the right trade for a debug build.
#
# NURL_SAN=1 (set by `build.sh --san`, or in the environment for a
# one-off build) forces a sanitized link: ASan + UBSan with the same
# flag set the main build uses, against a sidecar non-LTO runtime
# compiled with the same -fsanitize options. LTO is dropped because
# clang's combination of LTO + sanitizers produces opaque link-time
# diagnostics on NURL's cross-module function-pointer pattern.
LTO_FLAG="-flto"
RUNTIME_TO_LINK="$RUNTIME"
SAN_LINK_FLAGS=""
if [ "${NURL_SAN:-0}" = "1" ]; then
    LTO_FLAG=""
    SAN_LINK_FLAGS="-fsanitize=address,undefined -fsanitize-address-use-after-scope -fno-omit-frame-pointer -fno-sanitize-recover=all"
    SAN_RUNTIME="$SCRIPT_DIR/stdlib/runtime_san.o"
    if [ ! -f "$SAN_RUNTIME" ] || [ "$SCRIPT_DIR/stdlib/runtime.c" -nt "$SAN_RUNTIME" ]; then
        echo "[runtime-san] rebuilding stdlib/runtime_san.o (non-LTO, with ASan+UBSan)"
        CFLAGS_SAN="-O1 -g -fsanitize=address,undefined -fsanitize-address-use-after-scope -fno-omit-frame-pointer -fno-sanitize-recover=all"
        for sentinel_flag in NURL_HAVE_SQLITE3:sqlite3; do
            d="${sentinel_flag%%:*}"; p="${sentinel_flag##*:}"
            if pkg-config --exists "$p" 2>/dev/null; then
                CFLAGS_SAN="$CFLAGS_SAN -D$d $(pkg-config --cflags "$p")"
            fi
        done
        # shellcheck disable=SC2086
        cc_run $CFLAGS_SAN -c "$SCRIPT_DIR/stdlib/runtime.c" -o "$SAN_RUNTIME"
    fi
    RUNTIME_TO_LINK="$SAN_RUNTIME"
elif [ $DEBUG_INFO -eq 1 ]; then
    LTO_FLAG=""
    DBG_RUNTIME="$SCRIPT_DIR/stdlib/runtime_debug.o"
    if [ ! -f "$DBG_RUNTIME" ] || [ "$SCRIPT_DIR/stdlib/runtime.c" -nt "$DBG_RUNTIME" ]; then
        echo "[runtime-debug] rebuilding stdlib/runtime_debug.o (non-LTO, with -g)"
        CFLAGS_DBG="-O0 -g"
        for sentinel_flag in NURL_HAVE_SQLITE3:sqlite3; do
            d="${sentinel_flag%%:*}"; p="${sentinel_flag##*:}"
            if pkg-config --exists "$p" 2>/dev/null; then
                CFLAGS_DBG="$CFLAGS_DBG -D$d $(pkg-config --cflags "$p")"
            fi
        done
        # shellcheck disable=SC2086
        cc_run $CFLAGS_DBG -c "$SCRIPT_DIR/stdlib/runtime.c" -o "$DBG_RUNTIME"
    fi
    RUNTIME_TO_LINK="$DBG_RUNTIME"
fi
echo "[2/2] $LLFILE → $OUTBASE  ($OPT${LTO_FLAG:+ $LTO_FLAG}${DEBUG_FLAGS:+ $DEBUG_FLAGS}${SAN_LINK_FLAGS:+ $SAN_LINK_FLAGS}${EXTRA_LIBS:+ $EXTRA_LIBS})"
# `-flto` is required because stdlib/runtime.o is compiled with -flto
# (build.sh) and therefore carries LLVM bitcode instead of native code.
# The matching link-time flag here drives the LTO pipeline, inlining
# every vec_data / nurl_peek / nurl_poke / nurl_print across the
# runtime ↔ user-code boundary.
#
# `-Wl,--as-needed` drops DT_NEEDED entries for any auto-linked library
# the program does not actually reference a symbol from — so a program
# that imports nothing DB-related never inherits libpq/libsqlite3 just
# because the build machine had them. Positional: it must precede the
# `-l` libraries to govern them.
# shellcheck disable=SC2086
cc_run $OPT $LTO_FLAG -Wl,--as-needed $OPAQUE_FLAGS $DEBUG_FLAGS $SAN_LINK_FLAGS "$LLFILE" "$RUNTIME_TO_LINK" $EXTRA_OBJS -o "$OUTBASE" -lm -lpthread $DL_LIB $EXTRA_LIBS

echo ""
echo "Done: $OUTBASE"
