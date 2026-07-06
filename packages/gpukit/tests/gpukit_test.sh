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

# Device-resident layer (GkBuf + gkd_* kernels); prints SKIP without a backend.
if $NURL tests/devcheck.nu "$WORK/devcheck" >/dev/null 2>"$WORK/devbuild.err"; then
    "$WORK/devcheck" > "$WORK/dev.out" 2>&1
    if grep -q "^SKIP" "$WORK/dev.out"; then
        echo "  (device layer skipped — no backend)"
    elif python3 - "$WORK/dev.out" <<'PY'
import sys, numpy as np
rows={}
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if '|' not in ln or ln.startswith('backend'): continue
    n,d=ln.split('|'); rows[n]=np.array([float(x) for x in d.split(',')])
def ref(dt):
    a=np.arange(12,dtype=dt); b=np.arange(1,13,dtype=dt); s=dt(0.5)
    mm=(a.reshape(3,4)@b.reshape(4,3)).reshape(-1)
    e=np.exp(mm.reshape(3,3)-mm.reshape(3,3).max(1,keepdims=True)); smax=(e/e.sum(1,keepdims=True)).reshape(-1)
    return {"add":a+b,"muls":a*s,"sig":1/(1+np.exp(-a)),"mm":mm,"smax":smax,"sum":np.array([a.sum()])}
f=0
for tag,dt in (("f32",np.float32),("f64",np.float64)):
    for op,e in ref(dt).items():
        got=rows.get(f"{tag}_{op}")
        if got is None or not np.allclose(got,e.astype(float),rtol=1e-5,atol=1e-6): f+=1
print(f"{12-f}/12")
sys.exit(1 if f else 0)
PY
    then
        ok "device layer (GkBuf + gkd_*): 12/12 vs numpy"
    else
        bad "device layer vs numpy"
    fi
else
    bad "devcheck build"; tail -4 "$WORK/devbuild.err"
fi

echo "== gpukit tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
