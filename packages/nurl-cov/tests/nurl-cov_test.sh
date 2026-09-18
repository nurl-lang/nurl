#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  nurl-cov end-to-end tests.
#
#  Run from the package dir:  ./tests/nurl-cov_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
#       NURL_COV_DIFF_N  how many corpus programs to diff (default 12)
#
#  Two halves:
#
#   1. The CLI: build a fixture package's tests with coverage, run them,
#      and check the report, the LCOV tracefile, the JSON, the HTML and
#      the --fail-under gate.
#
#   2. The differential: for real programs from the compiler's own test
#      corpus, compare `nurl-cov gcov` byte for byte against
#      `llvm-cov gcov -b -c -p`. Two independent readers of the same two
#      files have to agree on every count, every branch and every
#      percentage — which is the only way to know that numbers nobody
#      can work out by hand are right.
#
#  The differential needs llvm-cov and a checkout of the compiler's test
#  corpus. Where either is missing it is reported as SKIP, loudly, and
#  the CLI half still runs.
# ============================================================
set -u
cd "$(dirname "$0")/.."

REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then
    :
elif [ -x "$REPO_ROOT/nurl.sh" ]; then
    NURL="$REPO_ROOT/nurl.sh"
    export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}"
else
    NURL="nurl"
fi
export NURL_CC="${NURL_CC:-$NURL}"

WORK="$(mktemp -d -t nurl-cov-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0
SKIP=0
ok()   { echo "  PASS $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP $1"; SKIP=$((SKIP+1)); }

echo "[1/4] build nurl-cov"
if ! $NURL -O0 src/main.nu "$WORK/nurl-cov" >/dev/null 2>"$WORK/build.err"; then
    echo "  build failed:"
    sed 's/^/    /' "$WORK/build.err"
    exit 1
fi
COV="$WORK/nurl-cov"
ok "nurl-cov builds"

# ── 2. the CLI, on a package whose coverage is known ────────────
echo "[2/4] run against a fixture package"
PKG="$WORK/pkg"
mkdir -p "$PKG/src" "$PKG/tests"
cat > "$PKG/src/lib.nu" <<'EOF'
@ twice i n → i {
    ^ * n 2
}

@ never_called i n → i {
    ^ + n 1
}
EOF
cat > "$PKG/tests/basic.nu" <<'EOF'
$ `src/lib.nu`

@ main → i {
    ? == ( twice 21 ) 42 { ^ 0 } {}
    ^ 1
}
EOF
cat > "$PKG/nurl.toml" <<'EOF'
[package]
name = "fixture"
version = "0.0.0"
EOF

( cd "$PKG" && "$COV" run --quiet --json cov.json --lcov cov.info --html cov.html ) \
    >"$WORK/run.out" 2>"$WORK/run.err"
RUN_RC=$?
if [ "$RUN_RC" = 0 ]; then ok "nurl-cov run succeeds"; else
    bad "nurl-cov run succeeds (exit $RUN_RC)"
    sed 's/^/    /' "$WORK/run.err"
fi

if grep -q '"objects":1' "$PKG/cov.json" 2>/dev/null; then
    ok "the JSON reports the one test binary"
else
    bad "the JSON reports the one test binary"
fi

# `twice` is called; `never_called` is not. The second one only appears
# at all because the build passes --no-dce.
if grep -q 'FNDA:1,twice' "$PKG/cov.info" 2>/dev/null; then
    ok "LCOV records the covered function"
else
    bad "LCOV records the covered function"
fi
if grep -q 'FNDA:0,never_called' "$PKG/cov.info" 2>/dev/null; then
    ok "LCOV records the function nothing calls, as zero"
else
    bad "LCOV records the function nothing calls, as zero"
fi
if grep -q '<table class="src">' "$PKG/cov.html" 2>/dev/null; then
    ok "the HTML report carries the annotated source"
else
    bad "the HTML report carries the annotated source"
fi

( cd "$PKG" && "$COV" report .nurl-cov --quiet --fail-under 100 ) >/dev/null 2>&1
if [ $? = 1 ]; then ok "--fail-under rejects a suite below the floor"; else
    bad "--fail-under rejects a suite below the floor"
fi
( cd "$PKG" && "$COV" report .nurl-cov --quiet --fail-under 10 ) >/dev/null 2>&1
if [ $? = 0 ]; then ok "--fail-under accepts a suite above the floor"; else
    bad "--fail-under accepts a suite above the floor"
fi

( cd "$PKG" && "$COV" report "$WORK/definitely-not-here" ) >/dev/null 2>&1
if [ $? = 2 ]; then ok "a missing coverage directory is a usage error, not a pass"; else
    bad "a missing coverage directory is a usage error, not a pass"
fi

# ── 3. a coverage build that was never run ──────────────────────
echo "[3/4] notes without data"
$NURL --coverage --no-dce -O0 tests/fixtures/sample.nu "$WORK/neverrun" \
    >/dev/null 2>"$WORK/neverrun.err"
if [ -f "$WORK/neverrun.gcno" ] && [ ! -f "$WORK/neverrun.gcda" ]; then
    OUT="$("$COV" report "$WORK" --quiet --all --json "$WORK/never.json" 2>&1)"
    if grep -q '"lines_hit":0' "$WORK/never.json" 2>/dev/null; then
        ok "a program that was built and never run covers nothing"
    else
        bad "a program that was built and never run covers nothing"
    fi
else
    bad "notes without data: the coverage build produced no .gcno"
    sed 's/^/    /' "$WORK/neverrun.err" 2>/dev/null | head -5
fi

# ── 4. differential against llvm-cov ────────────────────────────
echo "[4/4] differential against llvm-cov"
LLVM_COV="$(command -v llvm-cov || true)"
CORPUS="$REPO_ROOT/compiler/tests"
if [ -z "$LLVM_COV" ]; then
    skip "differential (llvm-cov is not installed)"
elif [ ! -d "$CORPUS" ]; then
    skip "differential (the compiler test corpus is not in this checkout)"
else
    N="${NURL_COV_DIFF_N:-12}"
    PROGRAMS="$(ls "$CORPUS"/*.nu 2>/dev/null \
        | grep -v '/diag_\|/borrow_\|/should_' | head -n "$N")"
    DIFF_OK=0
    DIFF_BAD=0
    FILES=0
    for src in $PROGRAMS; do
        name="$(basename "$src" .nu)"
        d="$WORK/diff/$name"
        mkdir -p "$d"
        # Both readers must see the same two files, so the object is built
        # once and neither is allowed to re-run the program.
        if ! $NURL --coverage --no-dce -O0 "$src" "$d/$name" >/dev/null 2>&1; then
            continue
        fi
        ( cd "$d" && timeout 60 "./$name" >/dev/null 2>&1 )
        [ -f "$d/$name.gcda" ] || continue
        ( cd "$d" && "$LLVM_COV" gcov -b -c -p "$name.gcda" >/dev/null 2>&1 )
        bad_here=0
        for g in "$d"/*.gcov; do
            [ -f "$g" ] || continue
            srcpath="$(sed -n '1s/^.*0:Source://p' "$g")"
            [ -n "$srcpath" ] || continue
            FILES=$((FILES+1))
            ( cd "$d" && "$COV" gcov "$name.gcno" ) > "$d/mine.all" 2>/dev/null
            # `nurl-cov gcov` prints every source in the object; pick the
            # one this .gcov describes.
            awk -v want="Source:$srcpath" '
                /^        -:    0:Source:/ { on = (index($0, want) > 0) }
                on { print }
            ' "$d/mine.all" > "$d/mine.one"
            if ! diff -q "$g" "$d/mine.one" >/dev/null 2>&1; then
                bad_here=1
                echo "    MISMATCH $name :: $srcpath"
                diff "$g" "$d/mine.one" 2>/dev/null | head -6 | sed 's/^/      /'
            fi
        done
        if [ "$bad_here" = 0 ]; then DIFF_OK=$((DIFF_OK+1)); else DIFF_BAD=$((DIFF_BAD+1)); fi
        rm -rf "$d"
    done
    if [ "$FILES" = 0 ]; then
        bad "the differential compared nothing — it did not actually run"
    elif [ "$DIFF_BAD" = 0 ]; then
        ok "$DIFF_OK programs, $FILES source files, identical to llvm-cov"
    else
        bad "$DIFF_BAD of $((DIFF_OK+DIFF_BAD)) programs differ from llvm-cov"
    fi
fi

echo "== nurl-cov tests: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" = 0 ]
