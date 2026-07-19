#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/convert_test.sh — proof of `nurllama convert` (HF → GGUF).
#
#  A miniature llada2_moe checkpoint is crafted by python struct
#  packing (tests/make_tiny_llada2.py — no shared code with the NURL
#  side), converted with `nurllama convert`, and the result is:
#    1. structurally verified with the gguf CLI (hostile-input parser)
#    2. checked key by key: architecture, MoE hyperparameters,
#       tokenizer ids, chat template
#    3. compared NUMERICALLY: every converted tensor is exported back
#       to f32 and matched against the python source values within the
#       encoding's own error bound (Q8_0: 0.65·d per block; F32/F16
#       paths exact / RNE) — including the 256-way expert fusion order
#       and the BF16 → f32 widening of the embedding.
#
#  Run from the package dir:  ./tests/convert_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t nurllama-convert.XXXXXX)"
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

echo "[1/3] build nurllama + gguf CLI"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"
if ! (cd ../gguf && $NURL src/main.nu "$WORK/gguf") >/dev/null 2>"$WORK/gbuild.err"; then
    echo "FAIL: could not build gguf CLI:"; tail -5 "$WORK/gbuild.err"; exit 1
fi
GG="$WORK/gguf"

echo "[2/3] craft the tiny checkpoint + convert"
mkdir -p "$WORK/hf"
python3 tests/make_tiny_llada2.py "$WORK/hf" > "$WORK/tensors.txt" || { echo "FAIL: crafting"; exit 1; }

if "$NL" convert "$WORK/hf" "$WORK/tiny.gguf" >/dev/null 2>"$WORK/conv.err"; then
    ok "convert exits 0"
else
    bad "convert exits 0"; cat "$WORK/conv.err"; exit 1
fi

echo "[3/3] verify the GGUF"
if "$GG" verify "$WORK/tiny.gguf" >/dev/null 2>&1; then
    ok "gguf verify accepts the file"
else
    bad "gguf verify accepts the file"
fi

ckkv() { # <key> <expected-substring> <label>
    local got
    got=$("$GG" kv "$WORK/tiny.gguf" "$1" 2>/dev/null)
    if printf '%s' "$got" | grep -qF "$2"; then
        ok "$3"
    else
        bad "$3 (got: $got)"
    fi
}
ckkv general.architecture "llada2" "architecture is llada2"
ckkv llada2.block_count "2" "block_count"
ckkv llada2.expert_count "8" "expert_count"
ckkv llada2.expert_used_count "2" "expert_used_count"
ckkv llada2.expert_group_count "2" "expert_group_count"
ckkv llada2.expert_group_used_count "1" "expert_group_used_count"
ckkv llada2.expert_gating_func "2" "gating func sigmoid"
ckkv llada2.expert_weights_scale "2.5" "expert_weights_scale"
ckkv llada2.leading_dense_block_count "1" "leading dense block"
ckkv llada2.rope.dimension_count "8" "partial rotary dim (16*0.5)"
ckkv llada2.rope.freq_base "600000" "rope base"
ckkv tokenizer.ggml.model "gpt2" "tokenizer model gpt2"
ckkv tokenizer.ggml.pre "bailingmoe2" "tokenizer pre bailingmoe2"
ckkv tokenizer.ggml.bos_token_id "295" "bos id"
ckkv tokenizer.ggml.eos_token_id "296" "eos id"
ckkv tokenizer.ggml.mask_token_id "297" "mask id"
ckkv tokenizer.ggml.padding_token_id "296" "pad id"
ckkv tokenizer.chat_template "HUMAN" "chat template"
ckkv diffusion.shift_logits "false" "diffusion.shift_logits"

# numeric parity: export every tensor and compare with the source
python3 - "$WORK" <<'EOF'
import json, subprocess, sys
import numpy as np

work = sys.argv[1]
tensors = np.load(f"{work}/hf/source_tensors.npy", allow_pickle=True).item()

NL_MAP = {}  # gguf name -> (source array, is_quantized)

def hf(name):
    return tensors[name]

cfg = json.load(open(f"{work}/hf/config.json"))
NLAY = cfg["num_hidden_layers"]; NE = cfg["num_experts"]

NL_MAP["token_embd.weight"] = "model.word_embeddings.weight"
NL_MAP["output.weight"] = "lm_head.weight"
NL_MAP["output_norm.weight"] = "model.norm.weight"
for L in range(NLAY):
    p = f"model.layers.{L}."
    NL_MAP[f"blk.{L}.attn_norm.weight"] = p + "input_layernorm.weight"
    NL_MAP[f"blk.{L}.attn_qkv.weight"] = p + "attention.query_key_value.weight"
    NL_MAP[f"blk.{L}.attn_q_norm.weight"] = p + "attention.query_layernorm.weight"
    NL_MAP[f"blk.{L}.attn_k_norm.weight"] = p + "attention.key_layernorm.weight"
    NL_MAP[f"blk.{L}.attn_output.weight"] = p + "attention.dense.weight"
    NL_MAP[f"blk.{L}.ffn_norm.weight"] = p + "post_attention_layernorm.weight"
    if L < cfg["first_k_dense_replace"]:
        NL_MAP[f"blk.{L}.ffn_gate.weight"] = p + "mlp.gate_proj.weight"
        NL_MAP[f"blk.{L}.ffn_up.weight"] = p + "mlp.up_proj.weight"
        NL_MAP[f"blk.{L}.ffn_down.weight"] = p + "mlp.down_proj.weight"
    else:
        NL_MAP[f"blk.{L}.ffn_gate_inp.weight"] = p + "mlp.gate.weight"
        NL_MAP[f"blk.{L}.exp_probs_b.bias"] = p + "mlp.gate.expert_bias"
        for kind in ("gate", "up", "down"):
            NL_MAP[f"blk.{L}.ffn_{kind}_exps.weight"] = [
                p + f"mlp.experts.{e}.{kind}_proj.weight" for e in range(NE)
            ]
        NL_MAP[f"blk.{L}.ffn_gate_shexp.weight"] = p + "mlp.shared_experts.gate_proj.weight"
        NL_MAP[f"blk.{L}.ffn_up_shexp.weight"] = p + "mlp.shared_experts.up_proj.weight"
        NL_MAP[f"blk.{L}.ffn_down_shexp.weight"] = p + "mlp.shared_experts.down_proj.weight"

def bf16_rne(a):
    bits = a.astype(np.float32).view(np.uint32)
    rounded = (bits + 0x7FFF + ((bits >> 16) & 1)).astype(np.uint32)
    return ((rounded >> 16).astype(np.uint32) << 16).view(np.float32)

fails = 0
for gname, src in NL_MAP.items():
    r = subprocess.run([f"{work}/gguf", "export", f"{work}/tiny.gguf", gname,
                        "-o", f"{work}/t.f32"], capture_output=True)
    if r.returncode != 0:
        print(f"  FAIL export {gname}: {r.stderr.decode().strip()}")
        fails += 1
        continue
    got = np.fromfile(f"{work}/t.f32", dtype=np.float32)
    if isinstance(src, list):
        want = np.stack([tensors[s] for s in src], axis=0).reshape(-1)
    else:
        want = tensors[src].reshape(-1)
    if gname == "token_embd.weight":
        want = bf16_rne(want).reshape(-1)  # source shard stored bf16
    if got.shape != want.shape:
        print(f"  FAIL {gname}: shape {got.shape} vs {want.shape}")
        fails += 1
        continue
    norm1d = gname.endswith("_norm.weight") or gname.endswith(".bias") or "gate_inp" in gname
    if norm1d:
        okv = np.array_equal(got, want.astype(np.float32))
        label = "exact f32"
    else:
        # Q8_0: per 32-block bound 0.65*d
        w = want.reshape(-1, 32)
        g = got.reshape(-1, 32)
        amax = np.abs(w).max(axis=1)
        d = amax / 127.0
        err = np.abs(g - w).max(axis=1)
        okv = bool((err <= 0.65 * d + 1e-6).all())
        label = "within Q8_0 bound"
    if okv:
        print(f"  PASS {gname} {label}")
    else:
        print(f"  FAIL {gname} {label}")
        fails += 1
sys.exit(1 if fails else 0)
EOF
PYRC=$?
if [ "$PYRC" = 0 ]; then
    ok "all tensors numerically match the checkpoint (incl. expert fusion + bf16)"
else
    bad "tensor numeric parity"
fi

# an f16 conversion also parses and verifies
if "$NL" convert "$WORK/hf" "$WORK/tiny-f16.gguf" --type f16 >/dev/null 2>&1 \
   && "$GG" verify "$WORK/tiny-f16.gguf" >/dev/null 2>&1; then
    ok "--type f16 converts and verifies"
else
    bad "--type f16 converts and verifies"
fi

# a directory without a checkpoint fails cleanly
if "$NL" convert /nonexistent "$WORK/x.gguf" >/dev/null 2>&1; then
    bad "missing dir rejected"
else
    ok "missing dir rejected"
fi

echo "== nurllama convert tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
