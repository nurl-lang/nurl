#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/agg_no_phi_ir.sh — a struct, an enum, an option or a
#  result never crosses a control-flow merge as a `phi` of the aggregate,
#  and an enum variant's tag is an immediate; checked in the IR.
#
#  agg_join_return_slots.nu proves the values are right. It cannot prove
#  HOW they travel, and that is the whole point (AGORA-853): LLVM takes a
#  stack slot apart field by field, and never takes a `phi` of an
#  aggregate apart — its tag or flag stays an `extractvalue` of a phi no
#  jump threading sees through, and a match on what an inlined function
#  just built dispatches a second time. A `ret %Agg` at every `^` is the
#  same shape one step later: SimplifyCFG merges the returns into one
#  block with exactly that phi. bench/payload_state_machine ran 416M
#  instructions that way and runs 253M without it.
#
#  POSITIVE markers are counted too (a gate that only looks for the
#  absence of a phi passes when nothing was emitted at all).
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="$SCRIPT_DIR/agg_join_return_slots.nu"

[ -x "$NURLC" ] || { echo "agg_no_phi_ir: $NURLC not found — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-58s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

(cd "$ROOT" && NURL_STDLIB="$ROOT" "$NURLC" "$SRC") > "$WORK/a.ll" 2> "$WORK/a.err" \
    || { echo "agg_no_phi_ir: compiling $SRC failed:"; cat "$WORK/a.err"; exit 1; }

# want <label> <regex> — at least one line of the IR matches.
want() {
    local n
    n=$(grep -cE "$2" "$WORK/a.ll")
    if [ "$n" -gt 0 ]; then note "$1" "ok ($n)"; else bad "$1" "no line matches /$2/"; fi
}
# none <label> <regex> — no line matches.
none() {
    local n
    n=$(grep -cE "$2" "$WORK/a.ll")
    if [ "$n" -eq 0 ]; then note "$1" "ok"; else bad "$1" "$n line(s) match /$2/"; fi
}
# in_fn <function> — that function's body, `define` to `}`.
in_fn() {
    awk -v f="@__nurl_fn.$1(" 'index($0, "define ") == 1 && index($0, f) { on = 1 } on { print } on && $0 == "}" { exit }' "$WORK/a.ll"
}
# rets <label> <function> <type regex> <count> — how many `ret`s of the
# aggregate the function has.
rets() {
    local n
    n=$(in_fn "$2" | grep -cE "^  ret $3 ")
    if [ "$n" -eq "$4" ]; then note "$1" "ok ($n)"; else bad "$1" "$n 'ret $3', expected $4"; fi
}

# ── No phi that merges aggregates ──────────────────────────────────
# The type of a phi is what stands between ` = phi ` and its first
# ` [ `: an aggregate opens with `%` (a named struct or enum), `{` (an
# option, a result, a closure pair) or `[N x` (an array) and does not
# end in `*` (a pointer to one is a scalar). A named type of ONE field —
# `%String = type { i8* }`, a Vec, a library handle — is one word, a
# scalar to the optimiser under another name: it keeps its phi (the
# module's own `%Name = type { … }` lines say which those are).
aggphi=$(awk '
    # %Name = type { one field }: no comma at the top level of its braces
    /^%[A-Za-z_.0-9]+ = type \{/ {
        name = $1; body = $0; sub(/^[^{]*\{/, "", body)
        depth = 0; commas = 0
        for (k = 1; k <= length(body); k++) {
            ch = substr(body, k, 1)
            if (ch == "{" || ch == "(" || ch == "[" || ch == "<") depth++
            else if (ch == "}" || ch == ")" || ch == "]" || ch == ">") depth--
            else if (ch == "," && depth == 0) commas++
        }
        if (commas == 0) oneword[name] = 1
        next
    }
    {
        i = index($0, " = phi ")
        if (i == 0) next
        t = substr($0, i + 7)
        c = substr(t, 1, 1)
        if (c != "%" && c != "{" && !(c == "[" && t ~ /^\[[0-9]+ x /)) next
        # the type ends where the incoming list ` [ ` begins, at depth 0
        depth = 0; end = 0
        for (k = 1; k <= length(t); k++) {
            ch = substr(t, k, 1)
            if (ch == "{" || ch == "(" || ch == "<") depth++
            else if (ch == "}" || ch == ")" || ch == ">") depth--
            else if (ch == "[" && k > 1 && depth == 0 && substr(t, k - 1, 1) == " " && substr(t, k + 1, 1) == " ") { end = k - 2; break }
            else if (ch == "[") depth++
            else if (ch == "]") depth--
        }
        if (end == 0) next
        ty = substr(t, 1, end)
        if (substr(ty, length(ty), 1) == "*") next
        if (ty in oneword) next
        # One incoming edge merges nothing (a join whose other arm
        # returned): LLVM reads such a phi as its value.
        if (index(substr(t, end + 1), "], [") == 0) next
        print
    }' "$WORK/a.ll")
if [ -z "$aggphi" ]; then
    note "no phi merging structs / enums / options / results" "ok"
else
    bad "no phi merging structs / enums / options / results" "$(printf '%s\n' "$aggphi" | wc -l) such phi(s):"
    printf '%s\n' "$aggphi" | head -5
fi
# (The scan sees phis at all: the scalar ones are still there, and so is
# the one-word String's — pick_s joins two.)
want "scalar phis are still phis"               ' = phi (i1|i64) \['
want "a one-word String keeps its phi"          ' = phi %String \[ %r[0-9]+, %[a-z_0-9]+ \], \['

# ── A join's arms store, the join loads ────────────────────────────
want "a join slot of an enum"                   '^  %r[0-9]+ = alloca %Shape$'
want "an arm stores its enum into the slot"     '^  store %Shape %r[0-9]+, %Shape\* %r[0-9]+$'
want "the join reads the slot"                  '^  %r[0-9]+ = load %Shape, %Shape\* %r[0-9]+$'
want "an option's join goes the same way"       '^  store \{ i1, i64 \} %r[0-9]+, \{ i1, i64 \}\* %r[0-9]+$'

# ── One exit block per function that returns an aggregate ──────────
want "a function's exit block"                  '^fn_ret_[0-9]+:$'
want "a closure body's exit block"              '^clo_ret_[0-9]+:$'
rets "classify: three returns, one ret"         classify '%Shape' 1
rets "step: five returns, one ret"              step '\{ i1, %P, %Fault \}' 1
rets "twice: two try exits and a return, one ret" twice '\{ i1, %P, %Fault \}' 1
rets "find_even: an early exit, one ret"        find_even '\{ i1, i64 \}' 1
rets "with_defer: a return above its defer, one ret" with_defer '%P' 1
# A tail call's result keeps its own `ret` beside the call — that is what
# lets the optimiser turn the recursion into a loop — so count_down has
# two: that one and the exit block's.
rets "count_down: the tail call keeps its ret"  count_down '%P' 2
# A body with ONE exit has no slot and no exit block: it compiles to the
# `ret` it always did (pick_p's only statement is its return).
rets "pick_p: one return, its own ret"          pick_p '%P' 1
if in_fn pick_p | grep -qE '^fn_ret_[0-9]+:$'; then
    bad "pick_p: no exit block for one return" "an exit block was emitted"
else
    note "pick_p: no exit block for one return" "ok"
fi
if in_fn count_down | grep -A1 -E '= tail call %P @__nurl_fn\.count_down\(' | grep -qE '^  ret %P %r[0-9]+'; then
    note "count_down: ret right after the tail call" "ok"
else
    bad "count_down: ret right after the tail call" "the tail call is not followed by its ret"
fi

# ── A variant's tag is an immediate ────────────────────────────────
none "no global per variant"                    '^@(Dot|Circle|Rect|Low|High) = '
none "no load of a variant's tag"               'load i64, i64\* @(Dot|Circle|Rect|Low|High)$'
want "a match compares the tag with a number"   '^  %r[0-9]+ = icmp eq i64 %r[0-9]+, [0-9]+$'
want "a literal builds its tag from a number"   'insertvalue %Shape zeroinitializer, i64 [0-9]+, 0$'

[ "$fails" -eq 0 ] && echo "agg_no_phi_ir: all assertions hold" || echo "agg_no_phi_ir: $fails FAILED"
exit "$fails"
