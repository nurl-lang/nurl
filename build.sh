#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  build.sh — bootstrap the NURL compiler and run the test
#             suite.  On full success, prints a single line:
#
#                 BUILD SUCCESS & TESTS PASSED
#
#  On any failure, the full build log or test-runner diff is
#  printed so the cause is visible.
#
#  Flags:
#    --no-tests  Skip the test suite at the end (Docker images, CI
#                stages that test elsewhere). Bootstrap fixed point
#                still has to hold or the build fails.
#    --san       Build runtime.o + every stage binary with
#                AddressSanitizer + UndefinedBehaviorSanitizer. Catches
#                use-after-free, double-free, OOB reads/writes, integer
#                overflow, null deref, etc. that the conservative
#                single-owner / auto-drop model cannot statically rule
#                out. ~3× slower at runtime; off by default. Exports
#                NURL_SAN=1 so run_tests.sh / nurl.sh / tools build
#                scripts pick up the same flags transparently.
#                Use ASAN_OPTIONS=detect_leaks=1 to enable leak checks
#                (off by default because some intentional stdlib globals
#                live until process exit).
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RUN_TESTS=1
SAN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-tests) RUN_TESTS=0; shift ;;
        --san)      SAN=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Sanitized builds skip the standard baseline-diff test runner — the
# baseline assumes plain output, and sanitizer reports would balloon
# it. The dedicated runner ./compiler/tests/run_san_tests.sh handles
# the sanitized corpus separately.
if (( SAN == 1 )); then
    RUN_TESTS=0
fi

# Sanitizer toolchain. -fno-omit-frame-pointer keeps stack traces
# readable; -fno-sanitize-recover=all turns soft UBSan diagnostics into
# hard fail-on-detection (so a single overflow exits the test binary
# instead of just printing to stderr); -fsanitize-address-use-after-scope
# catches use-after-scope on stack allocas, which matches NURL's
# closure-captures-stack-alloca pattern that we want to break loudly.
SAN_CFLAGS=""
SAN_LDFLAGS=""
if (( SAN == 1 )); then
    SAN_CFLAGS="-fsanitize=address,undefined -fsanitize-address-use-after-scope -fno-omit-frame-pointer -fno-sanitize-recover=all"
    SAN_LDFLAGS="-fsanitize=address,undefined"
    # LTO and sanitizers are theoretically compatible but in practice
    # clang's combination produces opaque link-time diagnostics for
    # NURL's pattern of cross-module function pointers. Disable LTO in
    # sanitized builds — the runtime/user-code inline win we lose isn't
    # the point of a san run anyway (we're after correctness, not perf).
    NO_LTO_IN_SAN=1
    export NURL_SAN=1
    # Disable LSan during the BUILD itself: nurlc_py / nurlc_self run
    # to completion and exit without freeing their str-pool / sym-arena
    # globals (an intentional process-lifetime allocation strategy).
    # LSan would flag every one as a leak and tank the build with
    # exit-1-on-detect. run_san_tests.sh re-enables leak detection on
    # demand via LSAN_DETECT_LEAKS=1 for the test corpus, where the
    # release-and-cleanup discipline is meaningfully different.
    export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0:halt_on_error=0:print_stacktrace=1"
    export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0"
else
    NO_LTO_IN_SAN=0
fi

# Helper that mints the right `-flto` or `-fno-lto` flag depending on
# sanitizer mode. Used in every clang invocation that compiles or links
# runtime.o-consuming code.
if (( NO_LTO_IN_SAN == 1 )); then
    LTO_FLAG=""
else
    LTO_FLAG="-flto"
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

fail() {
    echo "BUILD FAILED: $1"
    echo "===================================================="
    cat "$LOG"
    exit 1
}

log()  { echo "$*" >> "$LOG"; }
step() {
    local label="$1"; shift
    log ""
    log "[$label] $*"
    "$@" >> "$LOG" 2>&1 || fail "$label"
}

# ── Locate clang ─────────────────────────────────────────────
CLANG="clang"
if ! command -v clang &>/dev/null; then
    for candidate in /usr/lib/llvm/bin/clang /usr/local/bin/clang; do
        if [ -x "$candidate" ]; then CLANG="$candidate"; break; fi
    done
    if ! command -v "$CLANG" &>/dev/null; then
        echo "ERROR: clang not found"; exit 1
    fi
fi

mkdir -p build

# ── libcurl detection ────────────────────────────────────────
# When pkg-config knows about libcurl, build the runtime with the
# real HTTP transport. Otherwise the symbols still exist but every
# call returns HttpErr::Other(-1), and the link line below skips
# -lcurl.
CURL_CFLAGS=""
CURL_LIBS=""
if pkg-config --exists libcurl 2>/dev/null; then
    CURL_CFLAGS="-DNURL_HAVE_LIBCURL $(pkg-config --cflags libcurl)"
    CURL_LIBS="$(pkg-config --libs libcurl)"
    echo 1 > stdlib/runtime.curl
    log "[info] libcurl detected — HTTP transport enabled"
else
    rm -f stdlib/runtime.curl
    log "[info] libcurl not found — http_get/http_post will return HttpErr::Other"
fi

# ── libssl detection ─────────────────────────────────────────
# Same pattern as libcurl. With openssl present, the runtime's
# tcp_listen_tls / accept-with-handshake / SSL_read / SSL_write
# paths compile in; without it, the symbols still exist but every
# call returns NetErr::TLS_CONTEXT_INIT and the link line skips
# -lssl -lcrypto.
OPENSSL_CFLAGS=""
OPENSSL_LIBS=""
if pkg-config --exists openssl 2>/dev/null; then
    OPENSSL_CFLAGS="-DNURL_HAVE_OPENSSL $(pkg-config --cflags openssl)"
    OPENSSL_LIBS="$(pkg-config --libs openssl)"
    echo 1 > stdlib/runtime.openssl
    log "[info] openssl detected — TLS transport enabled (server-side)"
else
    rm -f stdlib/runtime.openssl
    log "[info] openssl not found — tcp_listen_tls will return NetErr::TLS_CONTEXT_INIT"
fi

# ── libsqlite3 detection ─────────────────────────────────────
# Same pattern as libcurl / openssl. With sqlite3 present, the
# runtime's `nurl_sqlite_*` bridge compiles in; without it, the
# symbols still exist but every call returns SqliteUnsupported and
# the link line skips -lsqlite3.
SQLITE3_CFLAGS=""
SQLITE3_LIBS=""
if pkg-config --exists sqlite3 2>/dev/null; then
    SQLITE3_CFLAGS="-DNURL_HAVE_SQLITE3 $(pkg-config --cflags sqlite3)"
    SQLITE3_LIBS="$(pkg-config --libs sqlite3)"
    echo 1 > stdlib/runtime.sqlite3
    log "[info] sqlite3 detected — SQLite FFI enabled"
else
    rm -f stdlib/runtime.sqlite3
    log "[info] sqlite3 not found — stdlib/ext/sqlite.nu will return SqliteUnsupported"
fi

# ── libpq detection ──────────────────────────────────────────
# PostgreSQL FFI is PURE NURL — `stdlib/ext/postgres.nu` declares
# every libpq symbol via `& `pq` @ ...` without any runtime.c bridge.
# Detection here exists only to (a) extend the default link line with
# -lpq so `nurlc` itself can build (it doesn't import postgres.nu —
# safe) and (b) emit the `stdlib/runtime.pq` sentinel that the new
# compile-time FFI-lib check consults: an attempt to compile a NURL
# program that uses postgres.nu without libpq-dev installed fails at
# compile time with a clear diagnostic, not a cryptic linker error.
PQ_LIBS=""
if pkg-config --exists libpq 2>/dev/null; then
    PQ_LIBS="$(pkg-config --libs libpq)"
    echo 1 > stdlib/runtime.pq
    log "[info] libpq detected — PostgreSQL FFI enabled"
else
    rm -f stdlib/runtime.pq
    log "[info] libpq not found — stdlib/ext/postgres.nu will fail at compile time"
fi

# ── zlib detection ──────────────────────────────────────────
# `stdlib/ext/compress.nu`'s `zlib_*` helpers (RFC 1950 stream format)
# are pure-NURL `& `z` @ compress2 / uncompress` calls. The `gzip_*`
# helpers (RFC 1952 file format) need libz's streaming API whose
# `z_stream` layout is platform-specific, so they go through the thin
# `nurl_gzip_compress` / `nurl_gzip_decompress` bridge in runtime.c §22
# — that path is enabled by `-DNURL_HAVE_ZLIB`. The sentinel below
# also satisfies the compile-time FFI-lib check so a NURL program that
# imports compress.nu without zlib1g-dev installed fails with a clear
# diagnostic rather than a cryptic linker error.
ZLIB_CFLAGS=""
ZLIB_LIBS=""
if pkg-config --exists zlib 2>/dev/null; then
    ZLIB_CFLAGS="-DNURL_HAVE_ZLIB $(pkg-config --cflags zlib)"
    ZLIB_LIBS="$(pkg-config --libs zlib)"
    echo 1 > stdlib/runtime.z
    log "[info] zlib detected — Gzip FFI enabled"
else
    rm -f stdlib/runtime.z
    log "[info] zlib not found — stdlib/ext/compress.nu's gzip_* will return CompressOther"
fi

# ── libzstd detection ──────────────────────────────────────
ZSTD_LIBS=""
if pkg-config --exists libzstd 2>/dev/null; then
    ZSTD_LIBS="$(pkg-config --libs libzstd)"
    echo 1 > stdlib/runtime.zstd
    log "[info] libzstd detected — Zstd FFI enabled"
else
    rm -f stdlib/runtime.zstd
    log "[info] libzstd not found — stdlib/ext/compress.nu's zstd_* will return CompressOther"
fi

# ── Build stages ─────────────────────────────────────────────
# `-flto` makes runtime.o emit LLVM bitcode so vec/string/io FFI calls
# inline across the runtime ↔ user-code boundary at link time. The
# matching `-flto` on every clang invocation that consumes runtime.o
# (this script, nurl.sh, compiler/tests/run_tests.sh, tools/*/build.sh)
# triggers the LTO link pipeline.
step "runtime"       bash -c "'$CLANG' -O2 $LTO_FLAG $SAN_CFLAGS $CURL_CFLAGS $OPENSSL_CFLAGS $SQLITE3_CFLAGS $ZLIB_CFLAGS -c stdlib/runtime.c -o stdlib/runtime.o"

# Under `-flto` the `runtime.o` above is LLVM bitcode, which a plain GNU
# `ld` cannot link. The LTO consumers (this script, nurl.sh, the test
# runner) pair it with `-flto` and are fine — but the playground's
# native-build endpoint links user IR with a stock `clang` + `ld` and
# needs a real ELF object. Emit `runtime.native.o` for that path: run
# codegen over the already-built bitcode (cheap — no C front-end re-run)
# so the feature defines stay identical to `runtime.o`. With LTO off
# `runtime.o` is already an ELF object, so just copy it.
if [ -n "$LTO_FLAG" ]; then
    step "runtime-native" "$CLANG" -O2 -c -x ir stdlib/runtime.o -o stdlib/runtime.native.o
else
    step "runtime-native" cp stdlib/runtime.o stdlib/runtime.native.o
fi

# Always build canvas.o. With SDL2 headers present we get the real
# native back-end (-DNURL_HAVE_SDL2); otherwise we compile a stub that
# prints a clear diagnostic and exits if the program actually calls
# into the canvas API. A marker file (stdlib/canvas.sdl2) tells nurl.sh
# whether to link -lSDL2 for canvas-using programs.
SDL2_INC=""
if   [ -f /usr/include/SDL2/SDL.h ]; then
    SDL2_INC="/usr/include"
elif pkg-config --exists sdl2 2>/dev/null; then
    # pkg-config gives us "-I/path/include/SDL2"; strip the -I and the
    # trailing /SDL2 so we can pass the parent directory.
    _sdl_cflags=$(pkg-config --cflags-only-I sdl2 | awk '{print $1}')
    SDL2_INC="${_sdl_cflags#-I}"
    SDL2_INC="${SDL2_INC%/SDL2}"
fi
if [ -n "$SDL2_INC" ]; then
    step "canvas"    "$CLANG" -c stdlib/canvas.c -DNURL_HAVE_SDL2 -I"$SDL2_INC" -o stdlib/canvas.o
    echo 1 > stdlib/canvas.sdl2
else
    step "canvas"    "$CLANG" -c stdlib/canvas.c -o stdlib/canvas.o
    rm -f stdlib/canvas.sdl2
    log "[info] libsdl2-dev not found — built canvas.o as a stub (canvas demos will link but abort at runtime)"
fi
step "clean"         rm -f build/nurlc_py.ll build/nurlc_py \
                          build/nurlc_self.ll build/nurlc_self \
                          build/nurlc_self2.ll build/nurlc_self2 \
                          build/nurlc

step "stage0 ir"     bash -c 'python compiler/nurlc.py --llvm compiler/nurlc.nu > build/nurlc_py.ll'
step "stage0 link"   "$CLANG" -O2 $LTO_FLAG $SAN_LDFLAGS build/nurlc_py.ll stdlib/runtime.o -lm -lpthread $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $PQ_LIBS $ZLIB_LIBS $ZSTD_LIBS -o build/nurlc_py

step "stage1 ir"     bash -c './build/nurlc_py compiler/nurlc.nu > build/nurlc_self.ll'
step "stage1 link"   "$CLANG" -O2 $LTO_FLAG $SAN_LDFLAGS build/nurlc_self.ll stdlib/runtime.o -lm -lpthread $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $PQ_LIBS $ZLIB_LIBS $ZSTD_LIBS -o build/nurlc_self

# Informational: python vs nurlc_py IR (not fatal).
if cmp -s build/nurlc_py.ll build/nurlc_self.ll; then
    log "[info] python and nurlc_py produce identical IR"
else
    log "[info] python and nurlc_py produce different IR (not fatal)"
fi

step "stage2 ir"     bash -c './build/nurlc_self compiler/nurlc.nu > build/nurlc_self2.ll'
step "stage2 link"   "$CLANG" -O2 $LTO_FLAG $SAN_LDFLAGS build/nurlc_self2.ll stdlib/runtime.o -lm -lpthread $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $PQ_LIBS $ZLIB_LIBS $ZSTD_LIBS -o build/nurlc_self2

# Fixed-point: nurlc_self must match nurlc_self2.
if ! cmp -s build/nurlc_self.ll build/nurlc_self2.ll; then
    {
        echo "Fixed point NOT reached — nurlc_self and nurlc_self2 differ."
        echo "Run: diff build/nurlc_self.ll build/nurlc_self2.ll"
    } >> "$LOG"
    fail "bootstrap fixed point"
fi

cp build/nurlc_self2 build/nurlc
ln -sf build/nurlc nurlc 2>/dev/null || cp build/nurlc nurlc

# ── nurlfmt ──────────────────────────────────────────────────
# Build the canonical source formatter on top of the freshly-
# bootstrapped nurlc. Treated as a soft step: failure here logs a
# warning but does not block the build, since the formatter is a
# tooling concern rather than a compiler invariant.
if bash "$SCRIPT_DIR/tools/nurlfmt/build.sh" >> "$LOG" 2>&1; then
    log "[info] nurlfmt built → build/nurlfmt"
    # Spot-check: a handful of representative files must still round-
    # trip through the formatter without changing their LLVM IR. The
    # full-tree gate lives in compiler/tests/nurlfmt_idempotent.sh
    # — run that manually for a complete sweep.
    if bash compiler/tests/nurlfmt_idempotent.sh \
            examples/fizzbuzz.nu examples/calculator.nu \
            stdlib/core/string.nu >> "$LOG" 2>&1; then
        log "[info] nurlfmt round-trip spot-check passed"
    else
        log "[warn] nurlfmt round-trip spot-check FAILED — see log"
    fi
else
    log "[warn] nurlfmt build failed; skipping"
fi

# ── Test suite ───────────────────────────────────────────────
if (( RUN_TESTS == 0 )); then
    if (( SAN == 1 )); then
        echo "BUILD SUCCESS (sanitized — run ./compiler/tests/run_san_tests.sh next)"
    else
        echo "BUILD SUCCESS (tests skipped via --no-tests)"
    fi
    exit 0
fi

if TEST_OUT="$(compiler/tests/run_tests.sh 2>&1)"; then
    echo "BUILD SUCCESS & TESTS PASSED"
    cp compiler/nurlc.nu compiler/nurlc_lastgood.nu
    exit 0
fi

echo "BUILD DIDN'T FAIL but TESTS FAILED"
echo "===================================================="
echo "$TEST_OUT"
exit 1
