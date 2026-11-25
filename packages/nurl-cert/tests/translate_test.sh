#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  nurl-cert's translator (src/tolean.nu, `nurl-cert translate`) (AGORA-1020).
#
#  Run from anywhere in a checkout:  packages/nurl-cert/tests/translate_test.sh
#  Needs: build/nurlc. Env: NURL_CERT a built nurl-cert (default: build it
#  into build/).
#
#  1. Fail closed: edits of a certify program's core IR that the translator
#     cannot render faithfully are reported `unsupported` (exit 2, the
#     reason on stderr), and a core IR it cannot read (a column that is not
#     an integer, fewer fields than a line counts, an `endfn` with no
#     function open, a missing word; and, deliberately stricter than
#     tools/ncore/tolean.py, an operand count past the words there are or
#     a block with no `end`) is exit 1, never a term
#     (tools/ncore/tolean_selftest.sh's cases, and more); a sparse variable
#     id or many variables cost no more than their number.
#  2. The reference: on every certify program the translator prints what
#     tools/ncore/tolean.py prints, byte for byte, with its exit code and
#     its message (skipped without python3; tools/ncore/tolean_parity.sh
#     compares the two over every hole probe as well).
# ============================================================
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
export NURL_STDLIB="$ROOT"
NURLC="$ROOT/build/nurlc"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
pass=0
ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

if [ -n "${NURL_CERT:-}" ]; then
    CERT="$NURL_CERT"
else
    CERT="$ROOT/build/nurl-cert"
    ( cd packages/nurl-cert && "$ROOT/nurl.sh" -O0 src/main.nu "$CERT" ) > "$TMP/build.log" 2>&1 \
        || { cat "$TMP/build.log"; echo "FAIL: nurl-cert did not build"; exit 1; }
fi

# tl CORE: the exit code of `nurl-cert translate CORE`; stdout in $TMP/out, stderr in $TMP/err.
tl() { "$CERT" translate "$1" > "$TMP/out" 2> "$TMP/err"; echo $?; }

# expect_unsupported NAME CORE REASON: exit 2, nothing on stdout, `unsupported: …REASON…` on stderr.
expect_unsupported() {
    rc=$(tl "$2")
    if [ "$rc" = 2 ] && [ ! -s "$TMP/out" ] && grep -q "^unsupported: .*$3" "$TMP/err"; then ok "$1"
    else bad "$1 (exit $rc; expected unsupported: …$3)"; sed 's/^/        /' "$TMP/err" | head -3; fi
}

echo "== 1. fail closed"
"$NURLC" --emit-core tools/ncore/certify/temporary_dropped_in_an_if_arm.nu > "$TMP/a.core" || { echo "FAIL: nurlc"; exit 1; }
rc=$(tl "$TMP/a.core")
if [ "$rc" = 0 ] && head -1 "$TMP/out" | grep -qx 'import C.A2Prog' && grep -q '^def P : Prog := ' "$TMP/out"; then
    ok "the unedited program translates"
else bad "the unedited program translates (exit $rc)"; fi

# A read of the arm's temporary after the `if` (its drop is the arm's
# last line, so the rest of the arm's own list is empty; github#2242's review).
awk '/^fn\tmain\t/{m=1} m && /^drop 3$/ && !d {print; print "eval call string_len 1 v4"; d=1; next} {print}' \
    "$TMP/a.core" > "$TMP/b.core"
expect_unsupported "a temporary read after an arm's drop" "$TMP/b.core" "read after its drop"

# A statement the translation has no rule for.
awk '/^fn\tmain\t/{m=1} m && /^scope$/ && !d {print; print "defer"; print "end"; d=1; next} {print}' \
    "$TMP/a.core" > "$TMP/c.core"
expect_unsupported "a statement with no rule (defer)" "$TMP/c.core" "main: statement defer"

# A construct the walk did not lower.
awk '/^fn\tmain\t/{m=1} m && /^scope$/ && !d {print; print "eval opaque x 0"; d=1; next} {print}' \
    "$TMP/a.core" > "$TMP/d.core"
expect_unsupported "an opaque rvalue" "$TMP/d.core" "main: rvalue opaque"

# A call of a function that is neither the program's nor an A2 construct.
awk '/^fn\tmain\t/{m=1} m && /^scope$/ && !d {print; print "eval call no_such_function 0"; d=1; next} {print}' \
    "$TMP/a.core" > "$TMP/e.core"
expect_unsupported "a call of a function not in the program" "$TMP/e.core" "call of no_such_function, not in the program"

# No entry.
sed 's/^fn\tmain\t/fn\tnot_main\t/' "$TMP/a.core" > "$TMP/f.core"
expect_unsupported "a program without main" "$TMP/f.core" "no main"

# A raw string held in a struct field (a view, which the field's type does not say).
printf 'ty\t%%S\t0\t1c----\tS\tA\t0\tF\t2\ta\ti64\tb\ti8*\tV\t0\nfn\tmain\ti64\t0\t1\tp.nu\t0\t\nv\t0\t1\t1\t0\t1\t-1\tx\t%%S\nret c\nendfn\n' > "$TMP/g.core"
expect_unsupported "a raw string in a struct field" "$TMP/g.core" "a raw string held in a struct field"

# A closure whose type takes a raw string.
printf 'fn\tmain\ti64\t0\t1\tp.nu\t0\t\nv\t0\t1\t1\t0\t1\t-1\tf\t{ i64 (i8*, i8*)*, i8* }\nret c\nendfn\n' > "$TMP/h.core"
expect_unsupported "a closure type over a raw string" "$TMP/h.core" "a raw string argument or result"

# A core IR the reader cannot read: exit 1, no term, no `unsupported`.
printf 'fn\tmain\ti64\t0\t1\tp.nu\t0\t\nv\t0\t1\t1\t0\t1\t-1\tx\ti64\nlet x use c\nret c\nendfn\n' > "$TMP/i.core"
rc=$(tl "$TMP/i.core")
if [ "$rc" = 1 ] && [ ! -s "$TMP/out" ] && grep -q '^nurl-cert: internal: ' "$TMP/err"; then ok "an unreadable core IR stops the translation (exit 1)"
else bad "an unreadable core IR stops the translation (exit $rc)"; sed 's/^/        /' "$TMP/err" | head -3; fi

# expect_internal NAME CORE REASON: exit 1, nothing on stdout, `nurl-cert: internal: …REASON…`
# (where tolean.py stops with an exception).
expect_internal() {
    rc=$(tl "$2")
    if [ "$rc" = 1 ] && [ ! -s "$TMP/out" ] && grep -q "^nurl-cert: internal: .*$3" "$TMP/err"; then ok "$1"
    else bad "$1 (exit $rc; expected internal: …$3)"; sed 's/^/        /' "$TMP/err" | head -3; fi
}

# A small program of two functions, edited below.
printf 'fn\thelper\ti64\t1\t1\tp.nu\t0\t\nv\t0\t0\t0\t0\t1\t-1\tx\ti64\nscope\nret c\nend\nendfn\nfn\tmain\ti64\t0\t2\tp.nu\t0\t\nscope\neval call helper 1 c\nret c\nend\nendfn\n' > "$TMP/s.core"
rc=$(tl "$TMP/s.core"); [ "$rc" = 0 ] && ok "the small program translates" || bad "the small program translates (exit $rc)"
sed 's/^fn\thelper\ti64\t1/fn\thelper\ti64\toops/' "$TMP/s.core" > "$TMP/n1.core"
expect_internal "a parameter count that is not an integer" "$TMP/n1.core" "parameter count is not an integer: oops"
sed 's/^fn\thelper\ti64\t1/fn\thelper\ti64\t99999999999999999999/' "$TMP/s.core" > "$TMP/n1b.core"
expect_internal "a parameter count past 64 bits" "$TMP/n1b.core" "parameter count is not an integer"
sed 's/^v\t0\t0\t0\t0/v\t0\t0\t0\tx1/' "$TMP/s.core" > "$TMP/n1c.core"
expect_internal "a variable's flags that are not an integer" "$TMP/n1c.core" "flags is not an integer: x1"
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t0\tF\t2\ta\ti64\n'; } > "$TMP/n2.core"
expect_internal "a ty line with fewer field pairs than it counts" "$TMP/n2.core" "fewer fields than it counts"
{ cat "$TMP/s.core"; printf 'endfn\n'; } > "$TMP/n4.core"
expect_internal "an endfn with no function open" "$TMP/n4.core" "an endfn with no function open"
# A sparse variable id: indexed sparsely (no billion-entry table), read as
# tolean.py reads it (the numbering past it).
awk '/^fn\tmain\t/{print; print "v\t1000000000\t2\t1\t0\t2\t-1\t\ti64"; next} {print}' "$TMP/s.core" > "$TMP/n3.core"
rc=$(timeout 20 "$CERT" translate "$TMP/n3.core" > "$TMP/out" 2> "$TMP/err"; echo $?)
if [ "$rc" = 0 ] && grep -q 'nvars := 1000000005 }' "$TMP/out"; then ok "a sparse variable id (10^9) costs nothing"
else bad "a sparse variable id (10^9) costs nothing (exit $rc)"; fi
sed 's/^v\t0\t0/v\t1000000000\t0/' "$TMP/s.core" > "$TMP/n3b.core"
expect_internal "a parameter with no v line (its only variable's id 10^9)" "$TMP/n3b.core" "a variable the function does not declare"
# A summary's parameter past 64 bits is no parameter (it does not wrap to 0).
{ cat "$TMP/s.core"; printf 'sum\thelper\t1\tsink=18446744073709551616\n'; } > "$TMP/n5.core"
rc=$(tl "$TMP/n5.core")
if [ "$rc" = 0 ] && grep -q 'params := \[(.inp, .int)\]' "$TMP/out" && ! grep -q '\.sink' "$TMP/out"; then ok "sink=2^64 marks no parameter"
else bad "sink=2^64 marks no parameter (exit $rc)"; fi
# Many variables: their first-seen order is found in n log n.
{ printf 'fn\tmain\ti64\t0\t1\tp.nu\t0\t\n'; seq 200000 -1 1 | awk '{print "v\t" $1 "\t2\t1\t0\t1\t-1\t\ti64"}'; printf 'scope\nret c\nend\nendfn\n'; } > "$TMP/n6.core"
rc=$(timeout 20 "$CERT" translate "$TMP/n6.core" > "$TMP/out" 2> "$TMP/err"; echo $?)
[ "$rc" = 0 ] && ok "200000 variables in reverse order translate in time" || bad "200000 variables in reverse order translate in time (exit $rc)"
# Intentional deviations from tolean.py (fail closed on malformed IR):
# an operand count past the operand words there are, and a block with no
# `end` (tolean.py reads both). An empty scope stays valid.
sed 's/^eval call helper 1 c$/eval call helper 1/' "$TMP/s.core" > "$TMP/r1.core"
expect_internal "a call that counts more operands than it has" "$TMP/r1.core" "malformed operands: main, statement 2: a call that counts 1 operands and has 0"
sed 's/^eval call helper 1 c$/eval call helper 0/' "$TMP/s.core" > "$TMP/r1b.core"
rc=$(tl "$TMP/r1b.core"); [ "$rc" = 0 ] && ok "a call that counts 0 operands and has 0 translates" || bad "a call that counts 0 operands and has 0 translates (exit $rc)"
sed 's/^eval call helper 1 c$/eval scalar 3 c c/' "$TMP/s.core" > "$TMP/r1c.core"
expect_internal "a scalar that counts more operands than it has" "$TMP/r1c.core" "malformed operands: main, statement 2: a scalar that counts 3 operands and has 2"
awk '/^fn\tmain\t/{m=1} m && /^end$/ && !d {d=1; next} {print}' "$TMP/s.core" > "$TMP/r2.core"
expect_internal "a scope with no end before the function's end" "$TMP/r2.core" "malformed block: main, statement 3: a block (scope) with no end"
awk '/^fn\tmain\t/{m=1} m && /^ret c$/ {print "end"} {print}' "$TMP/s.core" > "$TMP/r2b.core"
expect_internal "an end with no block open" "$TMP/r2b.core" "malformed block: main, statement 5: an end with no block open"
awk '/^fn\tmain\t/{m=1} m && /^scope$/ && !d {print; print "scope"; print "end"; d=1; next} {print}' "$TMP/s.core" > "$TMP/r2c.core"
rc=$(tl "$TMP/r2c.core"); [ "$rc" = 0 ] && ok "an empty scope translates" || bad "an empty scope translates (exit $rc)"

# Deliberately stricter than tolean.py too (`malformed`): counts below 0,
# a function left open, ids below 0, kinds outside 0-3.
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t0\tF\t-1\tV\t0\n'; } > "$TMP/q1.core"
expect_internal "a ty line's field count -1" "$TMP/q1.core" "malformed: a ty line's field count below 0"
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t0\tF\t0\tV\t0\n'; } > "$TMP/q1b.core"
rc=$(tl "$TMP/q1b.core"); [ "$rc" = 0 ] && ok "a ty line's field count 0 reads" || bad "a ty line's field count 0 reads (exit $rc)"
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t-2\tF\t0\tV\t0\n'; } > "$TMP/q1c.core"
expect_internal "a ty line's type-argument count -2" "$TMP/q1c.core" "malformed: a ty line's type-argument count below 0"
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t0\tF\t0\tV\t2\tA\t0\n'; } > "$TMP/q1d.core"
expect_internal "a ty line with fewer variants than it counts" "$TMP/q1d.core" "malformed: a ty line with fewer variants than it counts"
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t0\tF\t0\tV\t1\tA\t-1\n'; } > "$TMP/q1e.core"
expect_internal "a variant's payload count -1" "$TMP/q1e.core" "malformed: a variant's payload count below 0"
sed 's/^fn\tmain\ti64\t0/fn\tmain\ti64\t-1/' "$TMP/s.core" > "$TMP/q2.core"
expect_internal "a parameter count -1" "$TMP/q2.core" "malformed: an fn line's parameter count below 0"
sed -n 6p "$TMP/s.core" | grep -qx endfn || bad "the small program's first endfn is line 6"
awk 'NR==6 && /^endfn$/ {next} {print}' "$TMP/s.core" > "$TMP/q3.core"
expect_internal "an fn line while a function is open" "$TMP/q3.core" "malformed: an fn line while function helper is open"
head -n -1 "$TMP/s.core" > "$TMP/q4.core"
expect_internal "the input ending inside a function" "$TMP/q4.core" "malformed: the input ends inside function main"
sed 's/^eval call helper 1 c$/eval call helper -1/' "$TMP/s.core" > "$TMP/q5.core"
expect_internal "a call that counts -1 operands" "$TMP/q5.core" "malformed operands: main, statement 2: a call that counts -1 operands"
sed 's/^v\t0\t0\t0\t0/v\t-1\t0\t0\t0/' "$TMP/s.core" > "$TMP/q6.core"
expect_internal "a variable id -1" "$TMP/q6.core" "malformed: a variable's id below 0"
sed 's/^v\t0\t0\t0\t0/v\t0\t7\t0\t0/' "$TMP/s.core" > "$TMP/q7.core"
expect_internal "a variable kind 7" "$TMP/q7.core" "malformed: a variable's kind is not 0 to 3"
awk '/^fn\tmain\t/{m=1} m && /^ret c$/ {print "let -3 use c"} {print}' "$TMP/s.core" > "$TMP/q8.core"
expect_internal "a statement's variable id -3" "$TMP/q8.core" "malformed: a variable id below 0"

# Exact counts (CodeRabbit round 3): a ty line's type arguments are the
# columns between `A n` and `F`; a call has exactly its operands.
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t0\ti64\tF\t0\tV\t0\n'; } > "$TMP/x1.core"
expect_internal "a ty line with surplus type-argument columns" "$TMP/x1.core" "malformed: a ty line with more type arguments than it counts"
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t0\tF\t0\tV\t1\tA\t0\tjunk\n'; } > "$TMP/x3.core"
expect_internal "a ty line with columns after its variants" "$TMP/x3.core" "malformed: a ty line with columns after its variants"
{ cat "$TMP/s.core"; printf 'ty\t%%S\t0\t1c----\tS\tA\t0\tF\t0\tV\t0\n'; } > "$TMP/x3b.core"
rc=$(tl "$TMP/x3b.core"); [ "$rc" = 0 ] && ok "a ty line A 0 F 0 V 0 reads" || bad "a ty line A 0 F 0 V 0 reads (exit $rc)"
sed 's/^eval call helper 1 c$/eval call helper 0 v0/' "$TMP/s.core" > "$TMP/x2.core"
expect_internal "a call with an operand word past its count" "$TMP/x2.core" "malformed operands: main, statement 2: a call that counts 0 operands and has 1"

# A word a statement does not have.
sed 's/^ret c$/ret/' "$TMP/s.core" > "$TMP/n7.core"
expect_internal "a ret with no operand word" "$TMP/n7.core" "a word the core IR's statement does not have"

# AGORA-1030: an untracked number a statement consumes (a call's `c`
# argument) is bound at that statement, `(.letv q (.expr .any) …)`: inside a
# loop, each round's is any number again, not one value for every round.
cat > "$TMP/lp.nu" <<'NU'
$ `stdlib/core/vec.nu`
@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k 3 {
        ( vec_push [i] v 7 )
        = k + k 1
    }
    ^ ( vec_len [i] v )
}
NU
"$NURLC" --emit-core "$TMP/lp.nu" > "$TMP/lp.core" 2> /dev/null || bad "lp: nurlc --emit-core"
rc=$(tl "$TMP/lp.core")
q=$(grep -o '(.push [0-9]* [0-9]*)' "$TMP/out" | head -1 | sed 's/(.push [0-9]* \([0-9]*\))/\1/')
body=$(grep 'body := ' "$TMP/out" | grep '(.push ')
inloop=${body#*(.loop }
if [ "$rc" = 0 ] && [ -n "$q" ] && case "$inloop" in *"(.letv $q (.expr .any) (.seq (.push "*) true ;; *) false ;; esac \
    && case "${body%%(.loop *}" in *"(.letv $q "*) false ;; *) true ;; esac; then
    ok "a call's untracked argument in a loop is bound in the loop's body (fresh each round)"
else bad "a call's untracked argument in a loop is bound in the loop's body (exit $rc, temporary ${q:-none})"; fi

echo "== 1b. threads (A3; beyond tolean.py)"
# A program that spawns (`thread_spawn_owned`) is translated for A3: the
# closure of class `send`, a spawn wrapper, `def spawns`, the claim
# certOK3B. One that spawns nothing is translated as before.
cat > "$TMP/th1.nu" <<'NU'
$ `stdlib/std/thread.nu`
@ main → i {
    : i n 41
    : ( @ v ) body \ → v { : i m + n 1 }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}
NU
cat > "$TMP/th2.nu" <<'NU'
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
@ main → i {
    : ( Channel i ) ch ( chan_new [i] )
    : ( Channel i ) tx ( Channel_share [i] ch )
    : ( @ v ) body \ → v { ( chan_send [i] tx 41 ) }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    : i j ?? r { T t → ( thread_join t ) F _ → 1 }
    : ?i got ( chan_recv [i] ch )
    ^ ?? got { T v → + v j F → 0 }
}
NU
# The alias form moves the handle (nurlc: one owner); it is no share.
cat > "$TMP/th2b.nu" <<'NU'
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
@ main → i {
    : ( Channel i ) ch ( chan_new [i] )
    : ( Channel i ) tx ch
    : ( @ v ) body \ → v { ( chan_send [i] tx 41 ) }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}
NU
cat > "$TMP/th3.nu" <<'NU'
$ `stdlib/std/thread.nu`
$ `stdlib/core/string.nu`
@ main → i {
    : String s ( string_from `abc` )
    : ( @ v ) body \ → v { : i k ( string_len s ) }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    : i n ( string_len s )
    ^ ?? r { T t → ( thread_join t ) F _ → n }
}
NU
for k in th1 th2 th3; do "$NURLC" --emit-core "$TMP/$k.nu" > "$TMP/$k.core" 2> /dev/null || bad "$k: nurlc --emit-core"; done
for k in th1 th2; do
    rc=$(tl "$TMP/$k.core")
    if [ "$rc" = 0 ] && head -1 "$TMP/out" | grep -qx 'import C.Cert3' && grep -q '^def spawns : List Nat := \[[0-9]' "$TMP/out" \
        && grep -q 'params := \[(.sink, (.fn \[[0-9]*\] .send))\]' "$TMP/out" && grep -q '(.letcall [0-9]* [0-9]* \[[0-9]*\] ' "$TMP/out" \
        && grep -qx '#eval certOK3B P spawns entry 1' "$TMP/out" && ! grep -q '@W' "$TMP/out"; then ok "$k: a spawn translates for A3 (wrapper, send class, spawns)"
    else bad "$k: a spawn translates for A3 (exit $rc)"; sed 's/^/        /' "$TMP/err" | head -3; fi
done
grep -q '(.lockClone ' "$TMP/out" && ok "th2: Channel_share is a new share (lockClone)" || bad "th2: Channel_share is a new share (lockClone)"
"$NURLC" --emit-core "$TMP/th2b.nu" > "$TMP/th2b.core" 2> /dev/null || bad "th2b: nurlc --emit-core"
"$CERT" translate "$TMP/th2b.core" > "$TMP/th2b.out" 2> "$TMP/th2b.err"; rc=$?
if [ "$rc" = 0 ] && grep -q '^def spawns : List Nat := ' "$TMP/th2b.out" && head -1 "$TMP/th2b.out" | grep -qx 'import C.Cert3' \
    && ! grep -q '(.lockClone ' "$TMP/th2b.out"; then ok "th2b: a channel bound from another binding moves (no lockClone)"
else bad "th2b: a channel bound from another binding moves (exit $rc; an A3 term with no lockClone expected)"; sed 's/^/        /' "$TMP/th2b.err" | head -3; fi
expect_unsupported "a spawned closure capturing a String by name" "$TMP/th3.core" "__closure_1: a spawned closure capturing s by name"
# thread_spawn_owned copies the closure's environment; the translation moves
# the closure into the spawn wrapper: only a closure whose one use is the
# spawn is translated.
cat > "$TMP/th4.nu" <<'NU'
$ `stdlib/std/thread.nu`
@ main → i {
    : i n 41
    : ( @ v ) body \ → v { : i m + n 1 }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ( body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}
NU
cat > "$TMP/th5.nu" <<'NU'
$ `stdlib/std/thread.nu`
@ main → i {
    : i n 41
    : ( @ v ) body \ → v { : i m + n 1 }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    : !Thread ThreadErr r2 ( thread_spawn_owned body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}
NU
cat > "$TMP/th6.nu" <<'NU'
$ `stdlib/std/thread.nu`
@ run ( @ v ) f → v { ( f ) }
@ main → i {
    : i n 41
    : ( @ v ) body \ → v { : i m + n 1 }
    ( run body )
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}
NU
for k in th4 th5 th6; do "$NURLC" --emit-core "$TMP/$k.nu" > "$TMP/$k.core" 2> /dev/null || bad "$k: nurlc --emit-core"; done
expect_unsupported "a spawned closure called after its spawn" "$TMP/th4.core" "main: a spawned closure used again after its spawn (thread_spawn_owned copies the environment; the copy is not translated yet)"
expect_unsupported "a closure spawned twice" "$TMP/th5.core" "main: a spawned closure used again after its spawn"
expect_unsupported "a spawned closure passed to a helper" "$TMP/th6.core" "main: a spawned closure passed to a function that takes the ordinary closure type"
# Only operands count as a use: a callee and a field named like the spawned
# closure's variable (`v2` here) are not one, and the program translates.
cat > "$TMP/th7.nu" <<'NU'
$ `stdlib/std/thread.nu`
: P { i v2 i w }
@ v2 → i { ^ 1 }
@ main → i {
    : i n 41
    : ( @ v ) body \ → v { : i m + n 1 }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    : P q @ P { 1 2 }
    : i a . q v2
    : i b ( v2 )
    ^ ?? r { T t → + ( thread_join t ) + a b F _ → 1 }
}
NU
"$NURLC" --emit-core "$TMP/th7.nu" > "$TMP/th7.core" 2> /dev/null || bad "th7: nurlc --emit-core"
if grep -q '^let 3 call thread_spawn_owned 1 v2$' "$TMP/th7.core" && grep -q '^eval call v2 0$' "$TMP/th7.core" && grep -q ' v[0-9]*/v2$' "$TMP/th7.core"; then
    rc=$(tl "$TMP/th7.core")
    if [ "$rc" = 0 ] && grep -q '^def spawns : List Nat := ' "$TMP/out"; then ok "th7: a callee and a field named like the spawned closure are no use of it"
    else bad "th7: a callee and a field named like the spawned closure are no use of it (exit $rc)"; sed 's/^/        /' "$TMP/err" | head -3; fi
else bad "th7: the core IR names the spawned closure v2, a callee v2 and a field v2 (nurlc's numbering changed: update the test)"; fi

echo "== 2. the reference (tools/ncore/tolean.py)"
if command -v python3 > /dev/null; then
    n=0; same=0
    for f in tools/ncore/certify/*.nu; do
        k=$(basename "$f" .nu)
        # a threaded program is beyond tolean.py (A3, part 1b above)
        case "$k" in thread_*) continue ;; esac
        "$NURLC" --emit-core "$f" > "$TMP/$k.core" 2> /dev/null || { bad "$k: nurlc --emit-core"; continue; }
        n=$((n + 1))
        python3 tools/ncore/tolean.py "$TMP/$k.core" > "$TMP/$k.py.out" 2> "$TMP/$k.py.err"; prc=$?
        "$CERT" translate "$TMP/$k.core" > "$TMP/$k.nu.raw" 2> "$TMP/$k.nu.err"; nrc=$?
        # AGORA-1030: `.any` where tolean.py writes `(.lit 0)`; compared modulo that
        # (and where a literal temporary is bound: at its statement, not at
        # the top of the function, compared with those bindings dropped)
        # (a normalizer that fails is a failure, never two empty files equal)
        if ! python3 tools/ncore/norm_any.py --drop-temps "$TMP/$k.nu.raw" > "$TMP/$k.nu.out" \
            || ! python3 tools/ncore/norm_any.py --drop-temps "$TMP/$k.py.out" > "$TMP/$k.py.n"; then
            bad "$k: tools/ncore/norm_any.py failed"; continue
        fi
        mv "$TMP/$k.py.n" "$TMP/$k.py.out"
        if [ "$prc" = "$nrc" ] && cmp -s "$TMP/$k.py.out" "$TMP/$k.nu.out" && cmp -s "$TMP/$k.py.err" "$TMP/$k.nu.err"; then
            same=$((same + 1))
        else bad "$k: the translator differs from tolean.py (exit $nrc, tolean.py $prc)"; fi
    done
    [ "$same" = "$n" ] && ok "every certify program ($n) translates as tolean.py translates it"

else
    echo "  SKIP  python3 is not on PATH"
fi

echo
echo "translate: $pass passed, $fail failed"
[ "$fail" = 0 ]
