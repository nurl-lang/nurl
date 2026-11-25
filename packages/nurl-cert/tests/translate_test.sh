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
#     reason on stderr), and a core IR it cannot read is exit 1, never a
#     term (tools/ncore/tolean_selftest.sh's cases, and more).
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

echo "== 2. the reference (tools/ncore/tolean.py)"
if command -v python3 > /dev/null; then
    n=0; same=0
    for f in tools/ncore/certify/*.nu; do
        k=$(basename "$f" .nu)
        "$NURLC" --emit-core "$f" > "$TMP/$k.core" 2> /dev/null || { bad "$k: nurlc --emit-core"; continue; }
        n=$((n + 1))
        python3 tools/ncore/tolean.py "$TMP/$k.core" > "$TMP/$k.py.out" 2> "$TMP/$k.py.err"; prc=$?
        "$CERT" translate "$TMP/$k.core" > "$TMP/$k.nu.out" 2> "$TMP/$k.nu.err"; nrc=$?
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
