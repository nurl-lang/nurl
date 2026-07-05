#!/usr/bin/env bash
# ============================================================
#  tests/gpukit_test.sh — build tests/demo.nu (which exercises the whole
#  facade: elementwise add/mul, source-baked map + kernel-cache reuse,
#  bit-identical matmul, reduce-sum / dot, and a hand-written kernel through
#  the generic gk_run) and run it on the default backend and, when a C++
#  compiler is present, on the gpu package's CPU backend. Every bit-identical
#  op is checked with == against a host computation.
#
#  Run from the package dir:  ./tests/gpukit_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t gpukit-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/2] build tests/demo.nu"
if ! $NURL tests/demo.nu "$WORK/demo" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build demo:"; tail -8 "$WORK/build.err"; exit 1
fi

echo "[2/2] run on the available backends"
# Default backend (CUDA when a device is present, else CPU).
if "$WORK/demo" >"$WORK/def.out" 2>&1; then
    ok "default backend ($(grep -oE 'on (cuda|cpu)' "$WORK/def.out" | head -1)): $(grep -oE 'PASS [0-9]+ / FAIL [0-9]+' "$WORK/def.out")"
else
    bad "default backend"; sed 's/^/    /' "$WORK/def.out"
fi

# CPU backend — skip cleanly if there's no host C++ compiler.
if NURL_GPU=cpu "$WORK/demo" >"$WORK/cpu.out" 2>&1; then
    ok "CPU backend: $(grep -oE 'PASS [0-9]+ / FAIL [0-9]+' "$WORK/cpu.out")"
elif grep -q "need a C++ compiler" "$WORK/cpu.out"; then
    echo "  (CPU backend skipped — no host C++ compiler on PATH)"
else
    bad "CPU backend"; sed 's/^/    /' "$WORK/cpu.out"
fi

echo "== gpukit tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
