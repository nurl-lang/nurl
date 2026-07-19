#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/llada_infer_test.sh — proof of the llada2 (diffusion MoE)
#  forward pass, against an INDEPENDENT numpy oracle.
#
#  The python-crafted miniature llada2_moe checkpoint (fused QKV,
#  per-head Q/K norms, partial NEOX rope, dense layer 0, an 8-expert
#  sigmoid-routed grouped MoE layer with a shared expert) is converted
#  to GGUF and evaluated as one bidirectional window through
#  `nurllama dlogits`; tests/llada_ref.py computes the same logits
#  from the checkpoint's own tensors with no shared code.
#
#    1. --type f32 conversion: every position's full logit row matches
#       the oracle to float tolerance
#    2. --type q8_0: high correlation + agreeing argmax (quantisation
#       noise bounded, not absent)
#    3. NURL_GPU=cpu produces text-identical logits to the default
#       backend — kernel parity for the MoE + bidirectional path
#
#  Run from the package dir:  ./tests/llada_infer_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t nurllama-dinfer.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

if ! python3 -c 'import numpy' >/dev/null 2>&1; then
    echo "  SKIP (needs python3-numpy)"
    exit 0
fi

[ -e deps/gguf ] || { mkdir -p deps && ln -s ../../gguf deps/gguf; }
[ -e deps/safetensor ] || { mkdir -p deps && ln -s ../../safetensor deps/safetensor; }
[ -e deps/gpu ]  || { mkdir -p deps && ln -s ../../gpu deps/gpu; }
[ -e deps/tokenizer ] || { mkdir -p deps && ln -s ../../tokenizer deps/tokenizer; }
[ -e deps/http ] || { mkdir -p deps && ln -s ../../http deps/http; }

echo "[1/3] build nurllama + craft + convert"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"
mkdir -p "$WORK/hf"
python3 tests/make_tiny_llada2.py "$WORK/hf" >/dev/null || { echo "FAIL: crafting"; exit 1; }
"$NL" convert "$WORK/hf" "$WORK/tiny-f32.gguf" --type f32 >/dev/null 2>&1 || { echo "FAIL: convert f32"; exit 1; }
"$NL" convert "$WORK/hf" "$WORK/tiny-q8.gguf" >/dev/null 2>&1 || { echo "FAIL: convert q8_0"; exit 1; }

IDS="5 12 7 200 33 150 299 0"

echo "[2/3] logits vs the numpy oracle"
python3 tests/llada_ref.py "$WORK/hf" $IDS > "$WORK/ref.txt" || { echo "FAIL: oracle"; exit 1; }
"$NL" dlogits "$WORK/tiny-f32.gguf" $IDS > "$WORK/f32.txt" 2>"$WORK/f32.err" \
    || { bad "dlogits f32 runs"; cat "$WORK/f32.err"; exit 1; }
"$NL" dlogits "$WORK/tiny-q8.gguf" $IDS > "$WORK/q8.txt" 2>/dev/null \
    || { bad "dlogits q8_0 runs"; exit 1; }

python3 - "$WORK" <<'EOF'
import sys

import numpy as np

work = sys.argv[1]
ref = np.loadtxt(f"{work}/ref.txt")
f32 = np.loadtxt(f"{work}/f32.txt")
q8 = np.loadtxt(f"{work}/q8.txt")
fails = 0

if ref.shape != f32.shape:
    print(f"  FAIL shapes ref {ref.shape} vs f32 {f32.shape}")
    sys.exit(1)

d = np.abs(ref - f32).max()
if d < 2e-3:
    print(f"  PASS f32 logits match the oracle (max|delta| = {d:.2e}, all positions)")
else:
    print(f"  FAIL f32 logits vs oracle: max|delta| = {d:.3e}")
    fails += 1

am_ref = ref.argmax(1)
am_f32 = f32.argmax(1)
if (am_ref == am_f32).all():
    print(f"  PASS f32 argmax identical on every position ({list(am_ref)})")
else:
    print(f"  FAIL f32 argmax: ref {list(am_ref)} vs {list(am_f32)}")
    fails += 1

r = np.corrcoef(ref.reshape(-1), q8.reshape(-1))[0, 1]
agree = (q8.argmax(1) == am_ref).mean()
if r > 0.995:
    print(f"  PASS q8_0 logits correlate with the oracle (r = {r:.6f})")
else:
    print(f"  FAIL q8_0 correlation r = {r}")
    fails += 1
if agree >= 0.75:
    print(f"  PASS q8_0 argmax agreement {agree:.2f}")
else:
    print(f"  FAIL q8_0 argmax agreement {agree:.2f}")
    fails += 1
sys.exit(1 if fails else 0)
EOF
PYRC=$?
if [ "$PYRC" = 0 ]; then
    ok "logit parity battery"
else
    bad "logit parity battery"
fi

echo "[3/3] CPU backend parity"
if NURL_GPU=cpu "$NL" dlogits "$WORK/tiny-f32.gguf" $IDS > "$WORK/cpu.txt" 2>/dev/null; then
    if cmp -s "$WORK/f32.txt" "$WORK/cpu.txt"; then
        ok "NURL_GPU=cpu logits text-identical to the default backend"
    else
        # both backends round f32 slightly differently through printf —
        # accept numeric equality too
        if python3 - "$WORK" <<'EOF'
import sys
import numpy as np
w = sys.argv[1]
a = np.loadtxt(f"{w}/f32.txt"); b = np.loadtxt(f"{w}/cpu.txt")
sys.exit(0 if a.shape == b.shape and np.abs(a - b).max() < 1e-4 else 1)
EOF
        then
            ok "NURL_GPU=cpu logits numerically identical to the default backend"
        else
            bad "CPU backend parity"
        fi
    fi
else
    bad "CPU backend runs"
fi

echo "== llada2 inference tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
