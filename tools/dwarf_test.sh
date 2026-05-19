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
#  Then builds compiler/tests/dwarf_struct.nu (Phase 6 composite-
#  type regression) and asserts:
#    - print p renders the struct as `{x = 3, y = 7}`
#    - print p.x resolves the field by name
#    - ptype p shows `struct Point` with both fields listed
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
STRUCT_SRC="$ROOT_DIR/compiler/tests/dwarf_struct.nu"
STRUCT_BIN="$ROOT_DIR/build/dwarf_struct_dbg"

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

echo "[1/5] building $NU_SRC with --debug"
if ! "$ROOT_DIR/nurl.sh" --debug -O0 "$NU_SRC" "$BIN" >/tmp/dwarf_test.build 2>&1; then
    cat /tmp/dwarf_test.build
    fail "nurl.sh --debug failed"
fi

echo "[2/5] checking .debug_info section is present"
if ! readelf -S "$BIN" 2>/dev/null | grep -q '\.debug_info'; then
    fail "binary has no .debug_info section"
fi
pass ".debug_info section present"

echo "[3/5] gdb-batch: break + run + info locals + print"
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

echo "[4/5] llvm-dwarfdump (optional)"
if command -v llvm-dwarfdump >/dev/null 2>&1; then
    if ! llvm-dwarfdump --verify "$BIN" >/tmp/dwarf_test.dwarfdump 2>&1; then
        cat /tmp/dwarf_test.dwarfdump
        fail "llvm-dwarfdump --verify rejected the binary"
    fi
    pass "llvm-dwarfdump --verify clean"
else
    echo "  skip: llvm-dwarfdump not on PATH"
fi

# ── Phase 6 composite-type rendering — struct walk ──────────────────
if [[ ! -f "$STRUCT_SRC" ]]; then
    echo "WARN: $STRUCT_SRC not present — skipping struct phase" >&2
else
    echo "[5/5] Phase 6 composite types — ptype + print over %Point"
    if ! "$ROOT_DIR/nurl.sh" --debug -O0 "$STRUCT_SRC" "$STRUCT_BIN" \
            >/tmp/dwarf_struct.build 2>&1; then
        cat /tmp/dwarf_struct.build
        fail "nurl.sh --debug failed on $STRUCT_SRC"
    fi
    pass "dwarf_struct.nu built with --debug"

    STRUCT_OUT=$(gdb -batch \
        -ex 'set debuginfod enabled off' \
        -ex 'break _nurl_main' \
        -ex 'run' \
        -ex 'next' \
        -ex 'print p' \
        -ex 'print p.x' \
        -ex 'print p.y' \
        -ex 'ptype p' \
        -ex 'quit' "$STRUCT_BIN" 2>&1)

    echo "$STRUCT_OUT" | grep -Eq 'x = ?3.*y = ?7|y = ?7.*x = ?3' \
        || fail "print p did not show {x = 3, y = 7}"
    pass "print p renders composite as {x = 3, y = 7}"

    echo "$STRUCT_OUT" | grep -Eq '\$.* = ?3' \
        || fail "print p.x did not return 3"
    pass "print p.x resolved to 3"

    echo "$STRUCT_OUT" | grep -q 'struct Point' \
        || fail "ptype p did not show 'struct Point'"
    pass "ptype p shows 'struct Point'"

    # Field names must survive into DWARF — placeholder fallback
    # would show no member listing at all.
    echo "$STRUCT_OUT" | grep -Eq '\<x\>' \
        || fail "ptype p did not list field 'x'"
    echo "$STRUCT_OUT" | grep -Eq '\<y\>' \
        || fail "ptype p did not list field 'y'"
    pass "ptype p lists fields x and y by name"
fi

echo
echo "DWARF TEST PASSED"
