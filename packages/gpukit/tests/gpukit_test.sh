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

# Dev-layer op family (devops.nu + the dev.nu broadcast/bmm/gather/scatter
# cores): every operator against a numpy reference, on the default backend
# and the CPU backend.
check_ops() {  # $1 = opscheck output file
    python3 - "$1" <<'PY'
import sys, numpy as np
from math import erf
rows={}
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if '|' not in ln or ln.startswith('backend'): continue
    n,d=ln.split('|'); rows[n]=np.array([float(x) for x in d.split(',')])
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
def convt(X,W,b,ph,pw,sh,sw,OH,OW):
    Cin,Cout,kh,kw=W.shape; _,H,Wd=X.shape
    Y=np.zeros((Cout,OH,OW))
    for oc in range(Cout):
        for oy in range(OH):
            for ox in range(OW):
                acc=b[oc] if b is not None else 0.0
                for ic in range(Cin):
                    for ky in range(kh):
                        ty=oy+ph-ky
                        if ty%sh: continue
                        iy=ty//sh
                        if iy<0 or iy>=H: continue
                        for kx in range(kw):
                            tx=ox+pw-kx
                            if tx%sw: continue
                            ix=tx//sw
                            if ix<0 or ix>=Wd: continue
                            acc+=X[ic,iy,ix]*W[ic,oc,ky,kx]
                Y[oc,oy,ox]=acc
    return Y
def refs():
    out={}
    a=np.arange(24.).reshape(2,3,4)
    out['bcadd']=a+(1+10*np.arange(3.)).reshape(1,3,1)
    out['bcmuls']=a*0.5
    A=np.arange(12.).reshape(2,2,3)
    out['bmm']=A@(1+np.arange(12.)).reshape(2,3,2)
    out['bmmb']=A@(1+np.arange(6.)).reshape(3,2)
    d=np.arange(24.).reshape(2,4,3); idx=[2,0,3]
    out['gather']=d[:,idx,:]
    u=(100+np.arange(18.)).reshape(2,3,3)
    y=d.copy()
    for o in range(2):
        for g,ix in enumerate(idx): y[o,ix,:]=u[o,g,:]
    out['scatter']=y
    gA=np.arange(6.).reshape(2,3); gB=(1+np.arange(6.)).reshape(3,2); gC=np.array([2.,4.])
    out['gemm']=1.5*(gA@gB)+0.5*gC
    out['gemmt']=gA@(1+np.arange(6.)).reshape(2,3).T+gC
    out['gemmnb']=gA@gB
    X=(0.25*np.arange(32.)).reshape(2,4,4)
    W=(-1+0.125*np.arange(54.)).reshape(3,2,3,3)
    out['conv']=conv2d(X,W,np.array([0.5,1.,1.5]),1,1,1,1,4,4)
    out['convs2']=conv2d(X,W,None,0,0,2,2,1,1)
    out['convt']=convt((0.5*np.arange(8.)).reshape(2,2,2),
                       (-0.5+0.25*np.arange(24.)).reshape(2,3,2,2),
                       np.array([1.,2.,3.]),0,0,2,2,4,4)
    out['pool']=X.reshape(2,2,2,2,2).max(axis=(2,4))
    nx=np.arange(8.).reshape(2,4)
    out['bn']=(np.array([1.,1.5])[:,None]*(nx-np.array([1.,3.])[:,None])
               /np.sqrt(np.array([1.,2.])[:,None]+1e-5)+np.array([.25,.5])[:,None])
    ex=-2+0.5*np.arange(10.)
    out['lrelu']=np.where(ex>=0,ex,0.1*ex)
    out['clip']=np.clip(ex,0,3)
    out['erf']=np.array([erf(v) for v in ex])
    m=nx.mean(1,keepdims=True); v=((nx-m)**2).mean(1,keepdims=True)
    out['lnorm']=(nx-m)/np.sqrt(v+1e-5)*(1+0.25*np.arange(4.))+0.1*np.arange(4.)
    sx=(0.3*np.arange(12.)).reshape(2,3,2)
    e=np.exp(sx-sx.max(1,keepdims=True)); out['smax']=e/e.sum(1,keepdims=True)
    ddz=np.zeros((2,5,3)); ddz[:,1:3,:]=(1+np.arange(12.)).reshape(2,2,3)
    out['copyax']=ddz
    out['sliceax']=ddz[:,1:3,:]
    out['perm']=a.transpose(2,0,1)
    out['resize']=(1+np.arange(4.)).reshape(1,2,2).repeat(2,1).repeat(2,2)
    # bilinear, both corner conventions. These are torch's own numbers,
    # embedded rather than recomputed: align_corners changes the
    # coordinate mapping and not just the endpoints, so re-deriving the
    # expectation here would only restate the implementation. numpy has
    # no interpolate, and this suite must not need torch.
    #   torch.nn.functional.interpolate((1+0.7*arange(12)).reshape(1,1,3,4),
    #                                   size=(5,7), mode='bilinear', align_corners=…)
    out['bilac']=np.array([1.0,1.35,1.7,2.05,2.4,2.75,3.0999999999999996,2.4,2.75,3.1,
      3.4499999999999997,3.8,4.1499999999999995,4.5,3.8,4.15,4.5,4.85,5.199999999999999,
      5.549999999999999,5.8999999999999995,5.199999999999999,5.55,5.9,6.25,6.6,
      6.949999999999999,7.299999999999999,6.6,6.949999999999999,7.3,7.65,8.0,8.35,8.7])
    out['bilhc']=np.array([1.0,1.25,1.65,2.05,2.4499999999999997,2.8499999999999996,
      3.0999999999999996,2.12,2.3699999999999997,2.77,3.17,3.57,3.9699999999999998,4.22,
      3.8,4.05,4.449999999999999,4.85,5.249999999999999,5.6499999999999995,
      5.8999999999999995,5.4799999999999995,5.7299999999999995,6.129999999999999,
      6.529999999999999,6.929999999999999,7.329999999999999,7.579999999999999,6.6,6.85,
      7.249999999999999,7.6499999999999995,8.05,8.45,8.7])
    out['expand']=np.repeat(1+2*np.arange(3.),4)
    out['rl2']=np.sqrt((nx**2).sum(1))
    out['argmax']=np.array([4.,4.])
    ed=np.arange(12.).reshape(2,3,2)
    out['eosg']=np.stack([ed[0,1],ed[1,0]])
    return out
f=0; total=0
r=refs()
for tag in ("f32","f64"):
    for op,e in r.items():
        total+=1
        got=rows.get(f"{tag}_{op}")
        if got is None or not np.allclose(got,e.reshape(-1),rtol=1e-4,atol=1e-4):
            print(f"  FAIL {tag}_{op}"); f+=1
for name,e in (("i64_roundtrip",[5,-3,7,1000000000000,0,-8]),
               ("i64_sliceax",[7,1000000000000,0])):
    total+=1
    got=rows.get(name)
    if got is None or not np.allclose(got,np.array(e,dtype=float),rtol=1e-6,atol=0.5):
        print(f"  FAIL {name}"); f+=1
total+=1
g=rows.get("guards")
if g is None or len(g)!=2 or g[0]!=g[1]:
    print(f"  FAIL guards (fail-closed): {g}"); f+=1
print(f"{total-f}/{total}")
sys.exit(1 if f else 0)
PY
}

if $NURL tests/opscheck.nu "$WORK/opscheck" >/dev/null 2>"$WORK/opsbuild.err"; then
    "$WORK/opscheck" > "$WORK/ops.out" 2>&1
    if grep -q "^SKIP" "$WORK/ops.out"; then
        echo "  (op family skipped — no backend)"
    elif check_ops "$WORK/ops.out"; then
        ok "op family (default backend) vs numpy"
    else
        bad "op family (default backend) vs numpy"
    fi
    if NURL_GPU=cpu "$WORK/opscheck" > "$WORK/ops_cpu.out" 2>&1; then
        if check_ops "$WORK/ops_cpu.out"; then
            ok "op family (CPU backend) vs numpy"
        else
            bad "op family (CPU backend) vs numpy"
        fi
    elif grep -q "need a C++ compiler" "$WORK/ops_cpu.out"; then
        echo "  (op family CPU backend skipped — no host C++ compiler)"
    else
        bad "op family CPU backend"; sed 's/^/    /' "$WORK/ops_cpu.out" | head -8
    fi
else
    bad "opscheck build"; tail -4 "$WORK/opsbuild.err"
fi

# AddressSanitizer over the device layer + op family.
for t in devcheck opscheck; do
    if NURL_SAN=1 $NURL "tests/$t.nu" "$WORK/${t}_san" >/dev/null 2>"$WORK/${t}_san_build.err"; then
        "$WORK/${t}_san" >/dev/null 2>"$WORK/${t}_san.out" || true
        if grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/${t}_san.out"; then
            bad "ASan $t"; grep -m3 "ERROR\|leak" "$WORK/${t}_san.out"
        else
            ok "ASan $t clean"
        fi
    else
        echo "  (skipped ASan build for $t)"
    fi
done

echo "== gpukit tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
