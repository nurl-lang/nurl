#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/engine_end_line.sh — the line a use of an ended loan
#  names as where it ended is on a path that reaches the use, in the
#  ownership engine (`nurlc --engine`) and in its reference,
#  tools/ncore/check.py (AGORA-877).
#
#  The end records sit beside the state: an arm that leaves no path open
#  undoes its own, and a `break` or a `continue` carries its records to
#  where it goes — after the loop, the next round's head — not to what
#  follows the `?` it is an arm of. should_fail_engine_end_line.nu has one
#  function per case; its golden only says the walk refuses it.
#
#  The reference half needs python3 and is skipped without it (this
#  build needs no Python); the engine half always runs.
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="compiler/tests/should_fail_engine_end_line.nu"

[ -x "$NURLC" ] || { echo "engine_end_line: $NURLC not found — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-58s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

# function, the line of the use, the line it must name
WANT="break_arm 24 19
continue_arm 45 40
after_break 62 57
round_after_continue 72 75
foreach_break_arm 94 89
return_arm 109 104"

(cd "$ROOT" && NURL_STDLIB="$ROOT" "$NURLC" --engine "$SRC") > "$WORK/e.out" 2> "$WORK/e.err"
grep -E '^eng	err	' "$WORK/e.out" | sed -nE 's/^eng	err	([a-z_]+)	([0-9]+)	.*which ended at line ([0-9]+).*/\1 \2 \3/p' | sort -u > "$WORK/e.got"
[ -s "$WORK/e.got" ] || bad "the engine: findings" "none ($(head -1 "$WORK/e.err"))"

have_py=0
if command -v python3 > /dev/null 2>&1; then
    have_py=1
    (cd "$ROOT/tools/ncore" && PYTHONUTF8=1 NURLC="$NURLC" python3 show.py "$ROOT/$SRC") > "$WORK/r.out" 2>&1
    sed -nE "s/^   \('([a-z_]+)', ([0-9]+), '.*which ended at line ([0-9]+).*/\1 \2 \3/p" "$WORK/r.out" | sort -u > "$WORK/r.got"
    [ -s "$WORK/r.got" ] || bad "check.py: findings" "none ($(tail -1 "$WORK/r.out"))"
else
    note "check.py" "skipped (no python3)"
fi

while read -r fn use want; do
    got=$(awk -v f="$fn" -v u="$use" '$1 == f && $2 == u { print $3 }' "$WORK/e.got" | tr '\n' ' ')
    if [ "$got" = "$want " ]; then note "the engine: $fn, line $use" "ok (ended at $want)"; else bad "the engine: $fn, line $use" "names '${got% }', want $want"; fi
    if [ "$have_py" -eq 1 ]; then
        got=$(awk -v f="$fn" -v u="$use" '$1 == f && $2 == u { print $3 }' "$WORK/r.got" | tr '\n' ' ')
        if [ "$got" = "$want " ]; then note "check.py: $fn, line $use" "ok (ended at $want)"; else bad "check.py: $fn, line $use" "names '${got% }', want $want"; fi
    fi
done <<< "$WANT"

echo ""
if [ "$fails" -eq 0 ]; then echo "engine_end_line: OK"; exit 0; fi
echo "engine_end_line: $fails assertion(s) failed"
exit 1
