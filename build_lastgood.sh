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

if [[ -n "${PYTHON:-}" ]]; then
    if ! command -v "$PYTHON" &>/dev/null; then
        echo "ERROR: Python interpreter '$PYTHON' not found"; exit 1
    fi
else
    if command -v python3 &>/dev/null; then
        PYTHON="python3"
    elif command -v python &>/dev/null; then
        PYTHON="python"
    else
        echo "ERROR: python3 or python not found"; exit 1
    fi
fi

mkdir -p build

LINK_HELPER="$SCRIPT_DIR/build/nurl-build"
if [[ ! -x "$LINK_HELPER" ]]; then
    ZIG_BIN="${NURL_ZIG:-zig}"
    if command -v "$ZIG_BIN" &>/dev/null && [[ -f "$SCRIPT_DIR/build.zig" ]]; then
        step "nurl-build" "$ZIG_BIN" build nurl-build
    fi
fi
if [[ ! -x "$LINK_HELPER" ]]; then
    echo "ERROR: nurl-build helper not found at $LINK_HELPER" >&2
    echo "       Run: zig build nurl-build" >&2
    exit 1
fi

# ── Build stages ─────────────────────────────────────────────
step "runtime"       "$CLANG" -c stdlib/runtime.c -o stdlib/runtime.o
step "clean"         rm -f build/nurlc_py.ll build/nurlc_py \
                          build/nurlc_self.ll build/nurlc_self \
                          build/nurlc_self2.ll build/nurlc_self2 \
                          build/nurlc

step "stage0 ir"     env PYTHON="$PYTHON" bash -c '"$PYTHON" compiler/nurlc.py --llvm compiler/nurlc_lastgood.nu > build/nurlc_py.ll'
step "stage0 link"   "$LINK_HELPER" --opt -O2 --no-lto --runtime "$SCRIPT_DIR/stdlib/runtime.o" "$SCRIPT_DIR" "$SCRIPT_DIR/build/nurlc_py.ll" "$SCRIPT_DIR/build/nurlc_py"

step "stage1 ir"     bash -c './build/nurlc_py compiler/nurlc_lastgood.nu > build/nurlc_self.ll'
step "stage1 link"   "$LINK_HELPER" --opt -O2 --no-lto --runtime "$SCRIPT_DIR/stdlib/runtime.o" "$SCRIPT_DIR" "$SCRIPT_DIR/build/nurlc_self.ll" "$SCRIPT_DIR/build/nurlc_self"

# Informational: python vs nurlc_py IR (not fatal).
if cmp -s build/nurlc_py.ll build/nurlc_self.ll; then
    log "[info] python and nurlc_py produce identical IR"
else
    log "[info] python and nurlc_py produce different IR (not fatal)"
fi

step "stage2 ir"     bash -c './build/nurlc_self compiler/nurlc_lastgood.nu > build/nurlc_self2.ll'
step "stage2 link"   "$LINK_HELPER" --opt -O2 --no-lto --runtime "$SCRIPT_DIR/stdlib/runtime.o" "$SCRIPT_DIR" "$SCRIPT_DIR/build/nurlc_self2.ll" "$SCRIPT_DIR/build/nurlc_self2"

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
