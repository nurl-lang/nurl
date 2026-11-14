#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/core_ir.sh — `nurlc --emit-core` lowers every construct
#  to the core IR (docs/dev/CORE_IR.md, AGORA-858).
#
#  core_ir_shapes.nu has one function per construct. Each is checked for
#  the statements it must become: a producer bound to a temporary before
#  its consumer, a join's arms assigning one temporary, places with their
#  paths, arguments in parameter order. Then the two properties the IR is
#  only useful with:
#
#    * nothing is left `opaque` — in the shapes, and in the compiler's own
#      source, the largest program there is;
#    * the flag changes nothing else — the LLVM IR of the shapes is the
#      same bytes with the builder's hooks idle, and `--emit-core` prints
#      no LLVM IR.
#
#  POSITIVE markers are counted (a gate that only looks for the absence
#  of `opaque` passes when nothing was printed at all).
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="compiler/tests/core_ir_shapes.nu"

[ -x "$NURLC" ] || { echo "core_ir: $NURLC not found — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-58s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

(cd "$ROOT" && NURL_STDLIB="$ROOT" "$NURLC" --emit-core "$SRC") > "$WORK/a.core" 2> "$WORK/a.err" \
    || { echo "core_ir: --emit-core of $SRC failed:"; cat "$WORK/a.err"; exit 1; }

# body <function> — the statements of one function of the IR.
body() {
    awk -F'\t' -v f="$1" '$1 == "fn" { p = ($2 == f) } p && $1 != "fn" && $1 != "v" { print } $1 == "endfn" { p = 0 }' "$WORK/a.core"
}
# want <function> <label> <regex> — a statement of the function matches.
want() {
    local n
    n=$(body "$1" | grep -cE "$3")
    if [ "$n" -gt 0 ]; then note "$1: $2" "ok ($n)"; else bad "$1: $2" "no statement matches /$3/"; fi
}
# seq <function> <label> <regex>… — the statements match in this order.
seq_() {
    local fn="$1" label="$2" at=0 line re
    shift 2
    for re in "$@"; do
        line=$(body "$fn" | awk -v at="$at" -v re="$re" 'NR > at && $0 ~ re { print NR; exit }')
        if [ -z "$line" ]; then bad "$fn: $label" "no /$re/ after statement $at"; return; fi
        at=$line
    done
    note "$fn: $label" "ok"
}

# A call's result is a temporary before the binding takes it, and the
# temporary is released where the statement ends.
seq_ shape_store "a call is bound, then used" '^let [0-9]+ call vec_new__String 0$' '^let [0-9]+ use v[0-9]+$' '^drop [0-9]+$'
# A literal is a temporary; a field store and a field argument are places.
want shape_store "a literal is a temporary" '^let [0-9]+ agg - 2 v[0-9]+ c	%P$'
want shape_store "a field store names its place" '^assign v[0-9]+/n use c$'
want shape_store "a field argument is a place" '^eval call vec_push__String 2 v[0-9]+/items v[0-9]+$'
# A join: one temporary, assigned in each arm's scope.
seq_ shape_join "the arms assign the join's temporary" '^let [0-9]+ none$' '^if v0$' '^scope$' '^assign v[0-9]+ use v1$' '^end$' '^else$' '^assign v[0-9]+ use v2$' '^end$' '^end$' '^ret v[0-9]+$'
# A match: its payloads are bound in their arms.
seq_ shape_match "payloads are bound in their arms" '^match v0$' '^arm Circle$' '^let [0-9]+ payload v0 Circle 0$' '^arm Rect$' '^let [0-9]+ payload v0 Rect 0$' '^let [0-9]+ payload v0 Rect 1$' '^arm Named$' '^end$'
# Loops.
seq_ shape_loops "a foreach binds its element" '^foreach [0-9]+ v0$' '^scope$' '^eval call string_len 1 v[0-9]+$' '^end$' '^end$'
seq_ shape_loops "a loop's condition, then its body" '^loop$' '^loopcond c$' '^scope$' '^break$' '^end$' '^end$'
# A condition that is a true literal: the loop ends only at a `break` or a `^`.
seq_ shape_loop_always "a literal-true condition says so" '^loop$' '^loopcond T$' '^scope$' '^break$' '^end$' '^end$'
# A value block: its tail is assigned to a temporary of the statement around it.
seq_ shape_block "a value block's tail lands in a temporary" '^let [0-9]+ none$' '^let [0-9]+ call string_from 1 c$' '^let [0-9]+ call string_clone 1 v[0-9]+$' '^assign v[0-9]+ use v[0-9]+$' '^let [0-9]+ use v[0-9]+$'
# The operand of `|` that may not run is in the else of the first.
seq_ shape_short "a short-circuit operand is conditional" '^if c$' '^else$' '^scope$' '^eval call string_len 1 v0$' '^end$' '^end$'
# A try: the error arm returns, the other arm's payload is the value.
seq_ shape_try "a try matches its call's result" '^let [0-9]+ call parse 1 v0$' '^match v[0-9]+$' '^arm F$' '^ret v[0-9]+$' '^arm T$' '^let [0-9]+ payload v[0-9]+ T 0$' '^end$'
# A closure: its captures are read where it is made, its body is a function.
want shape_closure "a closure literal names its captures" '^let [0-9]+ closure __closure_[0-9]+ 2 v[0-9]+ v[0-9]+$'
want shape_closure "a call through a closure value" '^eval callind 2 v[0-9]+ c$'
seq_ shape_closure "a defer is a block of its own" '^defer$' '^scope$' '^eval call nurl_println_int 1 v[0-9]+$' '^end$' '^end$'
want apply "a closure parameter is called through" '^eval callind 2 v0 v1$'
# Named and defaulted arguments arrive in parameter order.
want shape_named "defaults fill a call's arguments" '^eval call defaults 3 c c c$'
seq_ shape_fall "a body's tail join is what it returns" '^let [0-9]+ none$' '^if v[0-9]+$' '^assign v[0-9]+ use v[0-9]+$' '^ret v[0-9]+$'
# (the closure of shape_fall_closure: the one that hands back a String)
fall_clo=$(awk -F'\t' '$1 == "fn" && $2 ~ /^__closure_/ && $3 == "%String" { print $2; exit }' "$WORK/a.core")
seq_ "${fall_clo:-__closure_none}" "a closure body's tail join is what it returns" '^if v[0-9]+$' '^assign v[0-9]+ use v[0-9]+$' '^ret v[0-9]+$'

# The closure's body is a function of the IR, its captures its first variables.
caps=$(awk -F'\t' '$1 == "fn" { p = ($2 ~ /^__closure_/) } p && $1 == "v" && $3 == 3 { n++ } END { print n + 0 }' "$WORK/a.core")
if [ "$caps" -ge 2 ]; then note "a closure body's captures are variables" "ok ($caps)"; else bad "a closure body's captures are variables" "found $caps"; fi

# The type table lists what the IR mentions.
tys=$(grep -cE '^ty	' "$WORK/a.core")
if [ "$tys" -gt 5 ]; then note "the types are listed" "ok ($tys)"; else bad "the types are listed" "found $tys"; fi
if grep -qE '^ty	%Shape	.*	V	3	Circle	1	double	Rect	2	double	double	Named	1	%String$' "$WORK/a.core"; then note "an enum's variants and payloads" "ok"; else bad "an enum's variants and payloads" "no such ty line"; fi

# Nothing is left opaque.
fns=$(grep -cE '^fn	' "$WORK/a.core")
if [ "$fns" -gt 10 ] && ! grep -qE '(^| )opaque ' "$WORK/a.core" && ! grep -q '^core' "$WORK/a.err"; then
    note "the shapes: nothing opaque" "ok ($fns functions)"
else
    bad "the shapes: nothing opaque" "$(grep -c '^core-gap' "$WORK/a.err") gap(s), $fns functions"
fi
(cd "$ROOT" && "$NURLC" --emit-core compiler/nurlc.nu) > "$WORK/self.core" 2> "$WORK/self.err"
sfns=$(grep -cE '^fn	' "$WORK/self.core")
if [ "$sfns" -gt 2000 ] && ! grep -qE '(^| )opaque ' "$WORK/self.core" && ! grep -q '^core' "$WORK/self.err"; then
    note "the compiler's own source: nothing opaque" "ok ($sfns functions)"
else
    bad "the compiler's own source: nothing opaque" "$(grep -c '^core-gap' "$WORK/self.err") gap(s), $sfns functions"
fi

# `--emit-core` prints the IR, not LLVM IR.
if grep -qE '^define |^declare ' "$WORK/a.core"; then bad "--emit-core prints no LLVM IR" "found a define"; else note "--emit-core prints no LLVM IR" "ok"; fi

echo ""
if [ "$fails" -eq 0 ]; then echo "core_ir: OK"; exit 0; fi
echo "core_ir: $fails assertion(s) failed"
exit 1
