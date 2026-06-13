#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/nurlpkg_bench_smoke.sh — end-to-end smoke test for
#  `nurlpkg bench` (the C4 bench runner half).
#
#  Asserts the runner discovers benches/*.nu, compiles + runs each,
#  streams its stdout, prints a `ran N · failed M` summary, and exits
#  0 iff every bench compiled and exited 0. std/bench.nu itself is
#  covered separately by the bench_basic.nu corpus golden, so these
#  fixtures are import-free (CWD-independent).
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
    "$ROOT_DIR/tools/nurlpkg/build.sh" >/dev/null 2>&1 || { echo "ERROR: build nurlpkg first (./build.sh)." >&2; exit 2; }
fi
[[ -x "$DRIVER" ]] || { echo "ERROR: $DRIVER missing." >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "nurlpkg bench smoke: FAIL — $1"; echo "── stdout ──"; cat "$WORK/out.txt"; echo "── stderr ──"; cat "$WORK/err.txt"; exit 1; }

# ── case 1: two healthy benches → streamed output + exit 0 ──
mkdir -p "$WORK/proj/benches"
printf '@ main → i { ( nurl_print `ALPHA_MARK\\n` ) ^ 0 }\n' > "$WORK/proj/benches/alpha.nu"
printf '@ main → i { ( nurl_print `BETA_MARK\\n` ) ^ 0 }\n'  > "$WORK/proj/benches/beta.nu"

( cd "$WORK/proj" && NURL_CC="$DRIVER" "$NURLPKG" bench ) >"$WORK/out.txt" 2>"$WORK/err.txt"
RC=$?
grep -q "ALPHA_MARK" "$WORK/out.txt" || fail "alpha output not streamed"
grep -q "BETA_MARK"  "$WORK/out.txt" || fail "beta output not streamed"
grep -q "ran 2 · failed 0" "$WORK/out.txt" || fail "summary wrong"
[[ $RC -eq 0 ]] || fail "healthy benches should exit 0 (got $RC)"

# ── case 2: one bench exits nonzero → failed 1, exit 1 ──
printf '@ main → i { ( nurl_print `GAMMA_MARK\\n` ) ^ 2 }\n' > "$WORK/proj/benches/gamma.nu"
( cd "$WORK/proj" && NURL_CC="$DRIVER" "$NURLPKG" bench ) >"$WORK/out.txt" 2>"$WORK/err.txt"
RC=$?
grep -q "ran 2 · failed 1" "$WORK/out.txt" || fail "nonzero-exit bench not counted as failure"
[[ $RC -eq 1 ]] || fail "a failing bench should exit 1 (got $RC)"

# ── case 3: no benches/ dir → message + exit 1 ──
mkdir -p "$WORK/empty"
( cd "$WORK/empty" && NURL_CC="$DRIVER" "$NURLPKG" bench ) >"$WORK/out.txt" 2>"$WORK/err.txt"
RC=$?
[[ $RC -eq 1 ]] || fail "missing benches/ should exit 1 (got $RC)"
grep -q "no benchmarks\|no benches" "$WORK/err.txt" || fail "missing benches/ message absent"

echo "nurlpkg bench smoke: OK (discovery, streaming, summary, exit codes correct)"
exit 0
