#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/nurlpkg_test_smoke.sh — end-to-end smoke test for
#  `nurlpkg test` (the C3 user-facing test runner).
#
#  Builds a throwaway project with a tests/ tree exercising all four
#  verdict paths and asserts the runner's report + exit code:
#
#    * exit-0, no golden            → PASS
#    * golden matches stdout        → PASS
#    * golden mismatches stdout     → FAIL (output mismatch)
#    * nonzero exit, no golden      → FAIL (nonzero exit)
#
#  and that an all-passing tree exits 0 while any failure exits 1.
#
#  Fixtures use only the `nurl_print` builtin (no `$` imports) so they
#  compile from any CWD; the build driver is the repo's ./nurl.sh,
#  passed via $NURL_CC. Heavier than the .nu corpus (each fixture is
#  compiled by nurl.sh), so it is a standalone script.
#
#  Exit codes: 0 ok · 1 assertion failed · 2 environment problem.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NURLPKG="$ROOT_DIR/build/nurlpkg"
DRIVER="$ROOT_DIR/nurl.sh"

if [[ ! -x "$NURLPKG" ]]; then
    echo "building nurlpkg..." >&2
    if ! "$ROOT_DIR/tools/nurlpkg/build.sh" >/dev/null 2>&1; then
        echo "ERROR: could not build build/nurlpkg (run ./build.sh first)." >&2
        exit 2
    fi
fi
[[ -x "$DRIVER" ]] || { echo "ERROR: $DRIVER missing." >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mk_project() {
    rm -rf "$WORK/proj"; mkdir -p "$WORK/proj/tests/outputs"
    printf '@ main → i { ^ 0 }\n'                              > "$WORK/proj/tests/aaa_pass.nu"
    printf '@ main → i { ( nurl_print `hello\\n` ) ^ 0 }\n'    > "$WORK/proj/tests/bbb_golden_ok.nu"
    printf 'hello\n'                                           > "$WORK/proj/tests/outputs/bbb_golden_ok.txt"
}

fail() { echo "nurlpkg test smoke: FAIL — $1"; echo "── output ──"; cat "$WORK/out.txt"; exit 1; }

# ── case 1: a mixed tree (2 pass, 2 fail) → exit 1 ──
mk_project
printf '@ main → i { ( nurl_print `actual\\n` ) ^ 0 }\n' > "$WORK/proj/tests/ccc_golden_bad.nu"
printf 'expected\n'                                      > "$WORK/proj/tests/outputs/ccc_golden_bad.txt"
printf '@ main → i { ^ 3 }\n'                            > "$WORK/proj/tests/ddd_fail_exit.nu"

( cd "$WORK/proj" && NURL_CC="$DRIVER" "$NURLPKG" test ) >"$WORK/out.txt" 2>"$WORK/err.txt"
RC=$?
grep -q "PASS aaa_pass"                  "$WORK/out.txt" || fail "aaa_pass not PASS"
grep -q "PASS bbb_golden_ok"             "$WORK/out.txt" || fail "golden match not PASS"
grep -q "FAIL ccc_golden_bad (output mismatch)" "$WORK/out.txt" || fail "golden mismatch not flagged"
grep -q "FAIL ddd_fail_exit (nonzero exit)"     "$WORK/out.txt" || fail "nonzero exit not flagged"
grep -q "PASS 2 · FAIL 2"                "$WORK/out.txt" || fail "summary wrong"
[[ $RC -eq 1 ]] || fail "mixed tree should exit 1 (got $RC)"

# ── case 2: an all-passing tree → exit 0 ──
mk_project
( cd "$WORK/proj" && NURL_CC="$DRIVER" "$NURLPKG" test ) >"$WORK/out.txt" 2>"$WORK/err.txt"
RC=$?
grep -q "PASS 2 · FAIL 0" "$WORK/out.txt" || fail "all-pass summary wrong"
[[ $RC -eq 0 ]] || fail "all-pass tree should exit 0 (got $RC)"

# ── case 3: no tests/ dir → exit 1 with a clear message ──
mkdir -p "$WORK/empty"
( cd "$WORK/empty" && NURL_CC="$DRIVER" "$NURLPKG" test ) >"$WORK/out.txt" 2>"$WORK/err.txt"
RC=$?
[[ $RC -eq 1 ]] || fail "missing tests/ should exit 1 (got $RC)"
grep -q "no tests" "$WORK/err.txt" || fail "missing tests/ message absent"

echo "nurlpkg test smoke: OK (verdicts, goldens, exit codes, empty-tree all correct)"
exit 0
