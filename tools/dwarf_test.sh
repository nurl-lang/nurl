#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  dwarf_test.sh — verify DWARF debug-info emission end-to-end.
#
#  Builds compiler/tests/dwarf_basic.nu with `nurl.sh --debug` and
#  drives gdb in batch mode to assert the basics work:
#    - source-level breakpoint on a NURL function name resolves
#    - `info locals` shows a `:` binding by name
#    - the binary carries a .debug_info ELF section
#    - llvm-dwarfdump (when installed) parses the section cleanly
#
#  Gracefully skips with exit 0 when gdb is missing — DWARF
#  tooling is a host concern, not a build invariant.
#
#  Usage: ./tools/dwarf_test.sh
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NU_SRC="$ROOT_DIR/compiler/tests/dwarf_basic.nu"
BIN="$ROOT_DIR/build/dwarf_basic_dbg"

if ! command -v gdb >/dev/null 2>&1; then
    echo "SKIP: gdb not found on PATH — DWARF behavioural test skipped"
    exit 0
fi

if [[ ! -f "$NU_SRC" ]]; then
    echo "ERROR: $NU_SRC not present" >&2
    exit 1
fi

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

echo "[1/4] building $NU_SRC with --debug"
if ! "$ROOT_DIR/nurl.sh" --debug -O0 "$NU_SRC" "$BIN" >/tmp/dwarf_test.build 2>&1; then
    cat /tmp/dwarf_test.build
    fail "nurl.sh --debug failed"
fi

echo "[2/4] checking .debug_info section is present"
if ! readelf -S "$BIN" 2>/dev/null | grep -q '\.debug_info'; then
    fail "binary has no .debug_info section"
fi
pass ".debug_info section present"

echo "[3/4] gdb-batch: break + run + info locals + print"
GDB_OUT=$(gdb -batch \
    -ex 'set debuginfod enabled off' \
    -ex 'break square' \
    -ex 'run' \
    -ex 'info args' \
    -ex 'info locals' \
    -ex 'next' \
    -ex 'print sq' \
    -ex 'backtrace' \
    -ex 'quit' "$BIN" 2>&1)

echo "$GDB_OUT" | grep -q 'Breakpoint 1.*square' \
    || fail "breakpoint did not resolve to function 'square'"
pass "break square resolved to source"

echo "$GDB_OUT" | grep -q 'dwarf_basic\.nu' \
    || fail "gdb did not associate frames with dwarf_basic.nu"
pass "frames carry source-file association"

echo "$GDB_OUT" | grep -Eq 'sq = ?49' \
    || fail "print sq did not return 49 (expected square(7) = 49)"
pass "print sq returned 49"

echo "[4/4] llvm-dwarfdump (optional)"
if command -v llvm-dwarfdump >/dev/null 2>&1; then
    if ! llvm-dwarfdump --verify "$BIN" >/tmp/dwarf_test.dwarfdump 2>&1; then
        cat /tmp/dwarf_test.dwarfdump
        fail "llvm-dwarfdump --verify rejected the binary"
    fi
    pass "llvm-dwarfdump --verify clean"
else
    echo "  skip: llvm-dwarfdump not on PATH"
fi

echo
echo "DWARF TEST PASSED"
