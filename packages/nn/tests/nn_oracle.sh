#!/usr/bin/env bash
# packages/grad/tests/lora_oracle.sh — the PyTorch float64 oracle for the
# LoRA transformer block (built from nn primitives). tests/nn_dump.nu prints every input pool, the
# loss, and all 14 adapter gradients as f64 bit patterns; torch rebuilds the
# IDENTICAL graph in float64 from those exact bits and autograds it. Loss
# and every adapter gradient must agree to 1e-11 relative (op order inside
# torch differs, so this is a tolerance check, not a bit check).
# Skips (exit 0) when the reference venv with torch is missing.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PY="$HOME/dev/python-scripts-runner/venv/bin/python"
export NURL_STDLIB="$REPO"

if [ ! -x "$PY" ] || ! "$PY" -c 'import torch' 2>/dev/null; then
    echo "[nn-oracle] SKIP — no torch venv"; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

( cd "$HERE" && "$REPO/nurl.sh" tests/nn_dump.nu "$TMP/dump" >/dev/null 2>&1 ) \
    || { echo "[nn-oracle] FAIL build"; ( cd "$HERE" && "$REPO/nurl.sh" tests/nn_dump.nu "$TMP/dump" 2>&1 | tail -5 ); exit 1; }
"$TMP/dump" > "$TMP/bits.txt" || { echo "[nn-oracle] FAIL dump"; exit 1; }

"$PY" - "$TMP/bits.txt" <<'PYEOF'
import sys, struct, torch
torch.set_default_dtype(torch.float64)

T, H, NH, KV, HD, IN, V, R = 8, 16, 4, 2, 4, 32, 16, 2
SCALE = 2.0 / R

d = {}
for line in open(sys.argv[1]):
    parts = line.split()
    d[parts[0]] = torch.tensor(
        [struct.unpack('<d', struct.pack('<q', int(b)))[0] for b in parts[1:]])

def m(name, r, c): return d[name].reshape(r, c)

AIN  = [H, H, H, NH*HD, H, H, IN]
AOUT = [NH*HD, KV*HD, KV*HD, H, IN, IN, H]
la, lb, A, B = d['la'], d['lb'], [], []
oa = ob = 0
for k in range(7):
    a = la[oa:oa+AIN[k]*R].reshape(AIN[k], R).clone().requires_grad_(True)
    b = lb[ob:ob+R*AOUT[k]].reshape(R, AOUT[k]).clone().requires_grad_(True)
    A.append(a); B.append(b); oa += AIN[k]*R; ob += R*AOUT[k]

x    = m('x', T, H)
wq, bq = m('wq', H, NH*HD), d['bq']
wk, bk = m('wk', H, KV*HD), d['bk']
wv, bv = m('wv', H, KV*HD), d['bv']
wo   = m('wo', NH*HD, H)
wg, wu, wd = m('wg', H, IN), m('wu', H, IN), m('wd', IN, H)
n1, n2, nf = d['n1'], d['n2'], d['nf']
wout = m('wout', H, V)
cos, sin = m('cosv', T, HD//2), m('sinv', T, HD//2)
mask = m('mask', T, T)
onehot = m('onehot', T, V)

def rms(x, w):
    return x / torch.sqrt((x*x).mean(dim=1, keepdim=True) + 1e-6) * w

def lora(x, w0, k):
    return x @ w0 + SCALE * ((x @ A[k]) @ B[k])

def rope(h):
    x1, x2 = h[:, :HD//2], h[:, HD//2:]
    return torch.cat([x1*cos - x2*sin, x2*cos + x1*sin], dim=1)

xn = rms(x, n1)
q  = lora(xn, wq, 0) + bq
kk = lora(xn, wk, 1) + bk
vv = lora(xn, wv, 2) + bv
ctx = []
for h in range(NH):
    kvi = h // (NH // KV)
    qh = rope(q[:, h*HD:(h+1)*HD])
    kh = rope(kk[:, kvi*HD:(kvi+1)*HD])
    vh = vv[:, kvi*HD:(kvi+1)*HD]
    sc = (qh @ kh.T) / (HD ** 0.5) + mask
    ctx.append(torch.softmax(sc, dim=1) @ vh)
attn = lora(torch.cat(ctx, dim=1), wo, 3)
x1r = x + attn
x1n = rms(x1r, n2)
gate = lora(x1n, wg, 4)
up   = lora(x1n, wu, 5)
act  = gate * torch.sigmoid(gate) * up
x2r  = x1r + lora(act, wd, 6)
xf   = rms(x2r, nf)
logits = xf @ wout
probs  = torch.softmax(logits, dim=1)
picked = (probs * onehot).sum(dim=1)
loss   = -(torch.log(picked).mean())
loss.backward()

def bits(v): return struct.unpack('<q', struct.pack('<d', float(v)))[0]
def rel(a, b):
    den = max(abs(a), abs(b), 1e-4)
    return abs(a - b) / den

nloss = 0.0
for line in open(sys.argv[1]):
    if line.startswith('loss '):
        nloss = struct.unpack('<d', struct.pack('<q', int(line.split()[1])))[0]

lrel = rel(float(loss), nloss)
print(f"[nn-oracle] loss torch {float(loss):.17g} nurl {nloss:.17g} rel {lrel:.3g}")
worst = lrel
for k in range(7):
    for tag, t in (('gA', A[k].grad), ('gB', B[k].grad)):
        nv = d[f'{tag}{k}']
        tv = t.reshape(-1)
        for i in range(len(nv)):
            r = rel(float(tv[i]), float(nv[i]))
            if r > worst: worst = r
print(f"[nn-oracle] worst grad rel {worst:.3g} over 14 adapters")
ok = worst < 1e-11
print("[nn-oracle]", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PYEOF
