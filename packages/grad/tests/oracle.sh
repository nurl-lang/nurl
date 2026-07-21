#!/usr/bin/env bash
# packages/grad/tests/oracle.sh — the PyTorch oracle. oracle_dump.nu builds a
# graph exercising every M1+M2 op and prints inputs + loss + parameter grads
# as f64 bit patterns; this script rebuilds the IDENTICAL graph in torch
# (float64, reading the exact same input bits) and compares every gradient
# element. Skips cleanly when the reference venv lacks torch.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export NURL_STDLIB="$REPO"
PY="$HOME/dev/python-scripts-runner/venv/bin/python"
if ! "$PY" -c "import torch" >/dev/null 2>&1; then
    echo "[grad-oracle] SKIP — no torch in the reference venv"; exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$HERE"
"$REPO/nurl.sh" tests/oracle_dump.nu "$TMP/dump" >/dev/null 2>&1 || { echo "[grad-oracle] FAIL build"; exit 1; }
"$TMP/dump" > "$TMP/out.txt" || { echo "[grad-oracle] FAIL run"; exit 1; }

"$PY" - "$TMP/out.txt" <<'PYEOF'
import struct, sys
import torch
torch.set_default_dtype(torch.float64)

bits2f = lambda b: struct.unpack('<d', struct.pack('<q', int(b)))[0]
ins, grads, loss_bits = {}, {}, None
for line in open(sys.argv[1]):
    p = line.split()
    if not p: continue
    if p[0] == 'in':      ins[p[1]] = [bits2f(x) for x in p[2:]]
    elif p[0] == 'grad':  grads[p[1]] = [bits2f(x) for x in p[2:]]
    elif p[0] == 'loss':  loss_bits = bits2f(p[1])

def T(name, shape, req):
    t = torch.tensor(ins[name]).reshape(shape)
    t.requires_grad_(req)
    return t

X  = T('X',  (8,5), False); Tt = T('T', (8,3), False)
W1 = T('W1', (5,7), True);  b1 = T('b1', (7,), True)
W2 = T('W2', (7,3), True);  b2 = T('b2', (3,), True)
A  = T('A',  (3,4), True);  Q  = T('Q', (2,2,3), False)
P  = T('P',  (2,3,2), True)

H  = torch.relu(X @ W1 + b1)
S  = torch.softmax(H @ W2 + b2, dim=1)
L1 = ((S - Tt)**2).mean()
Bt = torch.tanh(A.t())
C  = Bt.reshape(2, 6)
D  = C[0:2, 1:5]
E  = torch.cat([D, 0.5*D], dim=0)
L2 = (E*E).mean()
G  = torch.bmm(Q, P)
L3 = torch.sigmoid(G).sum()
loss = L1 + 0.3*L2 + 0.1*L3
loss.backward()

def cmp(name, got, want):
    got = torch.tensor(got); want = want.reshape(-1)
    rel = ((got - want).abs() / want.abs().clamp_min(1e-12)).max().item()
    absd = (got - want).abs().max().item()
    ok = rel < 1e-9 or absd < 1e-12
    print(f"[grad-oracle] {name:4s} max rel {rel:.3e} abs {absd:.3e} {'OK' if ok else 'MISMATCH'}")
    return ok

ok = True
lrel = abs(loss_bits - loss.item()) / max(abs(loss.item()), 1e-12)
print(f"[grad-oracle] loss nurl={loss_bits!r} torch={loss.item()!r} rel {lrel:.3e} {'OK' if lrel < 1e-12 else 'MISMATCH'}")
ok &= lrel < 1e-12
ok &= cmp('W1', grads['W1'], W1.grad)
ok &= cmp('b1', grads['b1'], b1.grad)
ok &= cmp('W2', grads['W2'], W2.grad)
ok &= cmp('b2', grads['b2'], b2.grad)
ok &= cmp('A',  grads['A'],  A.grad)
ok &= cmp('P',  grads['P'],  P.grad)
print("[grad-oracle] PASS" if ok else "[grad-oracle] FAILURES")
sys.exit(0 if ok else 1)
PYEOF
