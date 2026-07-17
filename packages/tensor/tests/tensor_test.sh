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

echo "[2b] device tensors (M3) — skipped cleanly without a GPU/backend"
if ! $NURL tests/dcheck.nu "$WORK/dcheck" >/dev/null 2>"$WORK/dbuild.err"; then
    echo "FAIL: could not build dcheck:"; tail -8 "$WORK/dbuild.err"; V=1
else
    "$WORK/dcheck" > "$WORK/dout.txt" 2>/dev/null
    if grep -q "^SKIP" "$WORK/dout.txt"; then
        echo "  (skipped — no device backend)"
    else
        python3 - "$WORK/dout.txt" <<'PY'
import sys, numpy as np
rows={}
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if '|' not in ln or ln.startswith('backend'): continue
    parts=ln.split('|'); rows[parts[0]]=np.array([float(x) for x in parts[-1].split(',')])
def conv2d(X,W,b,ph,pw,sh,sw,OH,OW):
    Cout,Cin,kh,kw=W.shape; _,H,Wd=X.shape
    Y=np.zeros((Cout,OH,OW))
    for oc in range(Cout):
        for oy in range(OH):
            for ox in range(OW):
                acc=b[oc] if b is not None else 0.0
                for ic in range(Cin):
                    for r in range(kh):
                        ih=oy*sh-ph+r
                        if ih<0 or ih>=H: continue
                        for s in range(kw):
                            iw=ox*sw-pw+s
                            if iw<0 or iw>=Wd: continue
                            acc+=X[ic,ih,iw]*W[oc,ic,r,s]
                Y[oc,oy,ox]=acc
    return Y
def ref(dt):
    a=np.arange(6,dtype=dt).reshape(2,3); w=np.arange(12,dtype=dt).reshape(3,4)
    x=np.tanh((a@w)*dt(0.05)+dt(0.5))*dt(2.0)
    e=np.exp(x-x.max(1,keepdims=True)); sm=e/e.sum(1,keepdims=True)
    ba=(np.arange(8192,dtype=dt)*dt(0.001)).reshape(128,64)
    bb=(np.arange(6144,dtype=dt)*dt(0.0005)).reshape(64,96)
    out={"rt":a.reshape(-1),"fwd":sm.reshape(-1),
         "relu":np.maximum(a-dt(2.5),0).reshape(-1),
         "sq":(a*a).reshape(-1),"ssum":np.array([(a*a).sum()]),
         "bigmm":np.array([(ba@bb).sum()])}
    # M5: broadcast / bmm / gather / scatter / conv / pool
    out["bcadd"]=a+(1+10*np.arange(3.))
    out["bcouter"]=np.arange(2.).reshape(2,1)*(1+np.arange(3.)).reshape(1,3)
    A=np.arange(12.).reshape(2,2,3)
    out["bmm"]=A@(1+np.arange(12.)).reshape(2,3,2)
    out["bmmb"]=A@(1+np.arange(6.)).reshape(3,2)
    out["bmmg"]=A.reshape(2,1,2,3)@(1+np.arange(18.)).reshape(1,3,3,2)
    d=np.arange(24.).reshape(2,4,3); idx=[2,0,3]
    out["gather"]=d[:,idx,:]
    u=(100+np.arange(18.)).reshape(2,3,3)
    y=d.copy()
    for o in range(2):
        for g,ix in enumerate(idx): y[o,ix,:]=u[o,g,:]
    out["scatter"]=y
    X=(0.25*np.arange(32.)).reshape(2,4,4)
    W=(-1+0.125*np.arange(54.)).reshape(3,2,3,3)
    out["conv"]=conv2d(X,W,np.array([0.5,1.,1.5]),1,1,1,1,4,4)
    out["convs2"]=conv2d(X,W,None,0,0,2,2,1,1)
    out["pool"]=X.reshape(2,2,2,2,2).max(axis=(2,4))
    return {k:np.asarray(v) for k,v in out.items()}
f=0; total=0
for tag,dt in (("f32",np.float32),("f64",np.float64)):
    for op,e in ref(dt).items():
        total+=1
        got=rows.get(f"{tag}_{op}")
        if got is None: print(f"  FAIL {tag}_{op}: missing"); f+=1; continue
        ok=np.allclose(got,e.astype(float).reshape(-1),rtol=1e-4,atol=1e-4)
        if not ok: print(f"  FAIL {tag}_{op}")
        f+=0 if ok else 1
total+=1
g=rows.get("guards")
if g is None or len(g)!=2 or g[0]!=g[1]:
    print(f"  FAIL guards (fail-closed): {g}"); f+=1
print(f"  {total-f}/{total} device ops match numpy (true float32 + float64 + fail-closed)")
sys.exit(1 if f else 0)
PY
        [ $? = 0 ] || V=1
    fi
fi

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
if NURL_SAN=1 $NURL tests/dcheck.nu "$WORK/dcheck_san" >/dev/null 2>"$WORK/dsan_build.err"; then
    "$WORK/dcheck_san" >/dev/null 2>"$WORK/dsan.out" || true
    if grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/dsan.out"; then
        echo "  FAIL ASan (device)"; grep -m3 "ERROR\|leak" "$WORK/dsan.out"; V=1
    else
        echo "  PASS ASan clean (device battery)"
    fi
else
    echo "  (skipped device ASan build)"
fi

[ "$V" = 0 ] && echo "== tensor tests: PASS" || echo "== tensor tests: FAIL"
exit $V
