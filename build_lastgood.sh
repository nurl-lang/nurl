#!/usr/bin/env bash
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

# ── Build stages ─────────────────────────────────────────────
# Python-free rescue build: start from the committed
# `compiler/nurlc_lastgood.ll` snapshot (boot binary), then run the
# self-host chain against `nurlc_lastgood.nu` (not `nurlc.nu`).
# Useful when current nurlc.nu is in a broken state and you want a
# known-good compiler to fall back on.
step "runtime"       "$CLANG" -c stdlib/runtime.c -o stdlib/runtime.o
step "clean"         rm -f build/nurlc_lastgood.bin \
                          build/nurlc_self.ll build/nurlc_self \
                          build/nurlc_self2.ll build/nurlc_self2 \
                          build/nurlc

step "stage0 link"   "$CLANG" -O2 compiler/nurlc_lastgood.ll stdlib/runtime.o -lm -o build/nurlc_lastgood.bin

step "stage1 ir"     bash -c './build/nurlc_lastgood.bin compiler/nurlc_lastgood.nu > build/nurlc_self.ll'
step "stage1 link"   "$CLANG" -O2 build/nurlc_self.ll stdlib/runtime.o -lm -o build/nurlc_self

step "stage2 ir"     bash -c './build/nurlc_self compiler/nurlc_lastgood.nu > build/nurlc_self2.ll'
step "stage2 link"   "$CLANG" -O2 build/nurlc_self2.ll stdlib/runtime.o -lm -o build/nurlc_self2

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

# ── Test suite ───────────────────────────────────────────────
if TEST_OUT="$(compiler/tests/run_tests.sh 2>&1)"; then
    echo "BUILD SUCCESS & TESTS PASSED"
    exit 0
fi

echo "BUILD DIDN'T FAIL but TESTS FAILED"
echo "===================================================="
echo "$TEST_OUT"
exit 1
