#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/bench_test.sh — the bench CLI runs and reports.
#    1. build
#    2. --list names all benchmarks
#    3. a full run prints a row per benchmark with a throughput unit
#    4. --json is a well-formed array with the expected fields
#    5. a name filter runs only the requested benchmark
#  Wall-time numbers are machine-dependent, so nothing here asserts a
#  specific throughput — only that every benchmark runs and reports.
#
#  Run from the package dir:  ./tests/bench_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bench"
fail() { echo "FAIL: $1"; exit 1; }

echo "[1/5] build"
$NURL src/main.nu "$BIN" >/dev/null 2>"$WORK/err" || { echo "build failed:"; tail -5 "$WORK/err"; exit 1; }

echo "[2/5] --list names every benchmark"
N=$("$BIN" --list | grep -c .)
[ "$N" -ge 5 ] || fail "--list returned only $N names"
"$BIN" --list | grep -q '^sha256$' || fail "--list missing sha256"

echo "[3/5] full run prints a throughput row per benchmark"
OUT="$("$BIN")" || fail "run exited non-zero"
for name in sha256 "json parse" "sort i64" "cbor decode" "utf8 decode" "int loop"; do
    echo "$OUT" | grep -qF "$name" || fail "no row for '$name'"
done
echo "$OUT" | grep -qE 'MB/s|M/s' || fail "no throughput unit in the table"

echo "[4/5] --json is a well-formed array"
"$BIN" --json > "$WORK/out.json" || fail "--json exited non-zero"
python3 - "$WORK/out.json" <<'PY' || fail "--json is not valid / complete"
import json,sys
rows=json.load(open(sys.argv[1]))
assert isinstance(rows,list) and len(rows)>=5, "expected an array of rows"
for r in rows:
    for k in ("name","ns_per_op","allocs_per_op","throughput","unit"):
        assert k in r, f"row missing {k}: {r}"
    assert r["ns_per_op"]>=0
print(f"   {len(rows)} rows, fields OK")
PY

echo "[5/5] a name filter runs only that benchmark"
F="$("$BIN" sha256)"
echo "$F" | grep -qF sha256 || fail "filter dropped sha256"
echo "$F" | grep -qF "int loop" && fail "filter should NOT run int loop"

echo "PASS: bench runs and reports"
