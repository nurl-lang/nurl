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
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

# ── Build stages ─────────────────────────────────────────────
step "runtime"       bash -c "'$CLANG' $CURL_CFLAGS $OPENSSL_CFLAGS -c stdlib/runtime.c -o stdlib/runtime.o"

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
step "stage0 link"   "$CLANG" -O2 build/nurlc_py.ll stdlib/runtime.o -lm -lpthread $CURL_LIBS $OPENSSL_LIBS -o build/nurlc_py

step "stage1 ir"     bash -c './build/nurlc_py compiler/nurlc.nu > build/nurlc_self.ll'
step "stage1 link"   "$CLANG" -O2 build/nurlc_self.ll stdlib/runtime.o -lm -lpthread $CURL_LIBS $OPENSSL_LIBS -o build/nurlc_self

# Informational: python vs nurlc_py IR (not fatal).
if cmp -s build/nurlc_py.ll build/nurlc_self.ll; then
    log "[info] python and nurlc_py produce identical IR"
else
    log "[info] python and nurlc_py produce different IR (not fatal)"
fi

step "stage2 ir"     bash -c './build/nurlc_self compiler/nurlc.nu > build/nurlc_self2.ll'
step "stage2 link"   "$CLANG" -O2 build/nurlc_self2.ll stdlib/runtime.o -lm -lpthread $CURL_LIBS $OPENSSL_LIBS -o build/nurlc_self2

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
if TEST_OUT="$(compiler/tests/run_tests.sh 2>&1)"; then
    echo "BUILD SUCCESS & TESTS PASSED"
    cp compiler/nurlc.nu compiler/nurlc_lastgood.nu
    exit 0
fi

echo "BUILD DIDN'T FAIL but TESTS FAILED"
echo "===================================================="
echo "$TEST_OUT"
exit 1
