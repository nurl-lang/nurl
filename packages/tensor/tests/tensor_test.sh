#!/usr/bin/env bash
# ============================================================
#  tests/tensor_test.sh — build tests/tcheck.nu (a battery of tensor ops,
#  all derived from arange) and check each result against numpy: creation,
#  reshape, broadcasting elementwise, 2-D matmul (CPU + a 128x128 GPU case),
#  transpose, a 3-D permute, axis/global reductions, and unary maps. Then
#  re-run under AddressSanitizer.
#
#  Run from the package dir:  ./tests/tensor_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
#  Skips cleanly if python3 + numpy are not installed.
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

if ! python3 -c "import numpy" 2>/dev/null; then
    echo "  (skipped — python3 + numpy not available)"; exit 0
fi

WORK="$(mktemp -d -t tensor-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/3] build tests/tcheck.nu"
if ! $NURL tests/tcheck.nu "$WORK/tcheck" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tcheck:"; tail -8 "$WORK/build.err"; exit 1
fi

echo "[2/3] run + verify against numpy"
"$WORK/tcheck" > "$WORK/out.txt" 2>/dev/null
python3 - "$WORK/out.txt" <<'PY'
import sys, numpy as np
rows={}
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if '|' not in ln: continue
    n,s,d=ln.split('|')
    rows[n]=(tuple(int(x) for x in s.split(',')) if s else (),
             np.array([float(x) for x in d.split(',')]) if d else np.array([]))
a=np.arange(6.).reshape(2,3); b=np.arange(3.).reshape(1,3); a24=np.arange(24.).reshape(2,3,4)
big=np.arange(16384.).reshape(128,128)
bmA=np.arange(12.).reshape(2,2,3); bmB=np.arange(12.).reshape(2,3,2); bmA1=np.arange(6.).reshape(1,2,3)
def _sm(x,ax):
    e=np.exp(x-x.max(ax,keepdims=True)); return e/e.sum(ax,keepdims=True)
exp={"a":a,"add":a+b,"mul":a*a,"aT":a.T,"matmul":a@a.T,"sum0":a.sum(0),"sum1":a.sum(1),
 "sum1k":a.sum(1,keepdims=True),"sumall":np.array(a.sum()),"mean0":a.mean(0),"max1":a.max(1),
 "min0":a.min(0),"relu":np.maximum(a-2.5,0),"exp":np.exp(a*0.1),"sig":1/(1+np.exp(-(a-2.0))),
 "perm":np.transpose(a24,(2,0,1)),"bigmm_sum":np.array((big@big).sum()),
 "bmm":bmA@bmB,"bmm_bc":bmA1@bmB,"softmax1":_sm(a,1),"slice":a[0:2,1:3],
 "cat0":np.concatenate([a,a],0),"cat1":np.concatenate([a,a],1),
 "argmax1":a.argmax(1).astype(float),"argmin0":a.argmin(0).astype(float)}
fails=0
for n,(shp,dat) in rows.items():
    if n not in exp: print(f"  FAIL {n}: no reference"); fails+=1; continue
    e=np.asarray(exp[n]); ev=e.reshape(-1)
    # 6-significant-figure print tolerance
    ok = tuple(int(x) for x in (e.shape or ()))==shp and ev.shape==dat.shape and np.allclose(ev,dat,rtol=1e-5,atol=1e-4)
    print(f"  {'PASS' if ok else 'FAIL'} {n}"); fails += 0 if ok else 1
print(f"  {len(rows)-fails}/{len(rows)} ops match numpy")
sys.exit(1 if fails else 0)
PY
V=$?

echo "[3/3] AddressSanitizer"
if NURL_SAN=1 $NURL tests/tcheck.nu "$WORK/tcheck_san" >/dev/null 2>"$WORK/san_build.err"; then
    "$WORK/tcheck_san" >/dev/null 2>"$WORK/san.out" || true
    if grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/san.out"; then
        echo "  FAIL ASan"; grep -m3 "ERROR\|leak" "$WORK/san.out"; V=1
    else
        echo "  PASS ASan clean (no errors, no leaks)"
    fi
else
    echo "  (skipped ASan build)"
fi

[ "$V" = 0 ] && echo "== tensor tests: PASS" || echo "== tensor tests: FAIL"
exit $V
