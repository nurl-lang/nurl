#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/journal_slot_cfg_ir.sh — a binding's panic-journal
#  registration is kept exactly where a panic can meet it while it is held
#  (agora #283).
#
#  The elision follows the function's branches from a registration to the
#  binding's end. It used to keep a registration whenever a call that may
#  panic stood anywhere between it and the END of the function, so a value
#  held only across calls that cannot panic stayed registered because of a
#  later one. journal_slot_cfg_ir.nu runs the program (its golden, which
#  also catches a panic and must stay clean under LSan); this reads its IR.
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="$SCRIPT_DIR/journal_slot_cfg_ir.nu"

[ -x "$NURLC" ] || { echo "journal_slot_cfg_ir: $NURLC not found — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-58s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

(cd "$ROOT" && NURL_STDLIB="$ROOT" "$NURLC" "$SRC") > "$WORK/j.ll" 2> "$WORK/j.err" \
    || { echo "journal_slot_cfg_ir: compiling $SRC failed:"; cat "$WORK/j.err"; exit 1; }

# body <fn> — the IR of function @__nurl_fn.<fn>.
body() { awk "/^define .*@__nurl_fn\\.$1\\(/,/^}/" "$WORK/j.ll"; }

# count <label> <fn> <regex> <op> <n> — the function exists and the number
# of its lines matching <regex> compares to <n> by <op> (eq / ge).
count() {
    local b n
    b=$(body "$2")
    [ -n "$b" ] || { bad "$1" "no function $2 in the IR"; return; }
    n=$(printf '%s\n' "$b" | grep -cE "$3")
    if [ "$n" -"$4" "$5" ]; then note "$1" "ok"; else bad "$1" "$n line(s) match /$3/"; fi
}

PUSH='call void @nurl_journal_push_drop2\('
count "early: none, though a call that may panic comes later" early "$PUSH" eq 0
count "across: kept, held across a call that may panic" across "$PUSH" ge 1
count "divided: kept, a zero check branches to a panic" divided "$PUSH" ge 1

[ "$fails" -eq 0 ] && echo "journal_slot_cfg_ir: all checks passed" || { echo "journal_slot_cfg_ir: $fails check(s) failed"; exit 1; }
