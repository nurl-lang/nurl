#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/global_atomic_ir.sh — scalar mutable globals are read
#  and written with relaxed atomics, checked in the IR.
#
#  global_scalar_threads.nu proves a writer thread and a reader agree on
#  the final values. It cannot prove the accesses in between were atomic —
#  a plain load and store race is undefined behaviour that usually prints
#  the same numbers. This greps the IR for the atomic forms, counting
#  POSITIVE markers (a gate that only looks for the absence of plain ones
#  passes when nothing was emitted at all), and checks that an immutable
#  constant is still an ordinary load.
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="$SCRIPT_DIR/global_scalar_threads.nu"

[ -x "$NURLC" ] || { echo "global_atomic_ir: $NURLC not found — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-52s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

(cd "$ROOT" && NURL_STDLIB="$ROOT" "$NURLC" "$SRC") > "$WORK/g.ll" 2> "$WORK/g.err" \
    || { echo "global_atomic_ir: compiling $SRC failed:"; cat "$WORK/g.err"; exit 1; }

# want <label> <regex> — at least one line of the IR matches.
want() {
    local n
    n=$(grep -cE "$2" "$WORK/g.ll")
    if [ "$n" -gt 0 ]; then note "$1" "ok ($n)"; else bad "$1" "no line matches /$2/"; fi
}
# none <label> <regex> — no line matches.
none() {
    local n
    n=$(grep -cE "$2" "$WORK/g.ll")
    if [ "$n" -eq 0 ]; then note "$1" "ok"; else bad "$1" "$n line(s) match /$2/"; fi
}

want "i64 counter: atomic load"   'load atomic i64, i64\* @g_count monotonic, align 8'
want "i64 counter: atomic store"  'store atomic i64 [^,]+, i64\* @g_count monotonic, align 8'
want "double: atomic store"       'store atomic double [^,]+, double\* @g_level monotonic, align 8'
want "u8: atomic store"           'store atomic i8 [^,]+, i8\* @g_byte monotonic, align 1'
want "string view: atomic store"  'store atomic i8\* [^,]+, i8\*\* @g_name monotonic, align 8'
want "bool: read as a byte"       'bitcast i1\* @g_done to i8\*'
want "bool: atomic byte load"     'load atomic i8, i8\* %[a-z0-9_]+ monotonic, align 1'
want "bool: atomic byte store"    'store atomic i8 %[a-z0-9_]+, i8\* %[a-z0-9_]+ monotonic, align 1'
none "no plain load of a mutable scalar"  '= load (i64|double|i8|i1|i8\*), [^ ]+ @g_(count|level|byte|done|name)$'
none "no plain store to a mutable scalar" '^  store (i64|double|i8|i1|i8\*) [^,]+, [^ ]+ @g_(count|level|byte|done|name)$'

[ "$fails" -eq 0 ] && echo "global_atomic_ir: all assertions hold" || echo "global_atomic_ir: $fails FAILED"
exit "$fails"
