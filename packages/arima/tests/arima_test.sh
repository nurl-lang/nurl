#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/arima_test.sh — the package's full test run:
#    1. arima_test.nu   algebra, the statsmodels oracle (recorded fixtures,
#                       no network, no Python), streaming, JSON, the batch
#                       driver, order selection
#    2. gpu_test.nu     the device evaluator is bit-identical to the CPU —
#                       on the gpu package's host C++ backend (NURL_GPU=cpu,
#                       always), and on a CUDA device when one is present
#    3. the CLI         fit and auto on the airline fixture
#
#  Run from the package dir:  ./tests/arima_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
#       NURL_SAN=1 for an AddressSanitizer/UBSan build
#  To regenerate the fixtures: tests/fixtures/make_fixtures.py with a
#  Python that has statsmodels (the reference venv).
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t arima-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/3] arima_test"
if ! $NURL tests/arima_test.nu "$WORK/arima_test" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build arima_test:"; tail -5 "$WORK/build.err"; exit 1
fi
if "$WORK/arima_test" > "$WORK/arima.out" 2>&1; then
    ok "arima_test ($(tail -1 "$WORK/arima.out"))"
else
    bad "arima_test"; grep -v '^ok' "$WORK/arima.out" | tail -8
fi

echo "[2/3] gpu_test"
if ! $NURL tests/gpu_test.nu "$WORK/gpu_test" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build gpu_test:"; tail -5 "$WORK/build.err"; exit 1
fi
if NURL_GPU=cpu "$WORK/gpu_test" > "$WORK/gpu_cpu.out" 2>&1; then
    ok "gpu_test on the CPU backend ($(tail -1 "$WORK/gpu_cpu.out"))"
else
    bad "gpu_test on the CPU backend"; tail -6 "$WORK/gpu_cpu.out"
fi
if "$WORK/gpu_test" > "$WORK/gpu.out" 2>&1; then
    ok "gpu_test on the default backend ($(head -1 "$WORK/gpu.out"); $(tail -1 "$WORK/gpu.out"))"
else
    bad "gpu_test on the default backend"; tail -6 "$WORK/gpu.out"
fi

echo "[3/3] CLI"
if ! $NURL src/main.nu "$WORK/arima" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build the arima CLI:"; tail -5 "$WORK/build.err"; exit 1
fi
python3 - "$WORK/air.txt" <<'PYEOF'
import json, sys
d = json.load(open("tests/fixtures/statsmodels_cases.json"))
open(sys.argv[1], "w").write("value\n" + "\n".join(str(v) for v in d["airline"]["y"]))
PYEOF
if "$WORK/arima" fit "$WORK/air.txt" --order 0,1,1 --seasonal 0,1,1,12 --horizon 3 > "$WORK/fit.json" 2>"$WORK/fit.err" \
   && python3 -c "import json,sys; d=json.load(open('$WORK/fit.json')); assert abs(d['theta'][0]+0.4018)<0.002 and len(d['forecast']['mean'])==3, d" ; then
    ok "arima fit: airline (0,1,1)(0,1,1)_12 with a 3-step forecast"
else
    bad "arima fit"; cat "$WORK/fit.err" | tail -3
fi
if "$WORK/arima" auto "$WORK/air.txt" --season 12 > "$WORK/auto.json" 2>"$WORK/auto.err" \
   && python3 -c "import json; d=json.load(open('$WORK/auto.json')); assert d['order']['d']==1 and d['order']['D']==1, d['order']"; then
    ok "arima auto: airline picks d=1, D=1"
else
    bad "arima auto"; cat "$WORK/auto.err" | tail -3
fi

echo "== arima tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
