#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/make_tiny_llada2.py — craft a miniature llada2_moe HF
#  checkpoint with NO shared code with the NURL converter: config.json,
#  tokenizer.json (byte-level BPE) and two safetensors shards written
#  by hand (struct-packed), deterministic values.
#
#  Usage: make_tiny_llada2.py <outdir>
#  Prints one "TENSOR name shape" line per source tensor so the test
#  can compare the converted GGUF against the same values.
# ============================================================
import json
import shutil
import struct
import sys

import numpy as np

OUT = sys.argv[1]
# Optional: build the checkpoint around a REAL tokenizer (dir holding
# tokenizer.json + tokenizer_config.json) — vocab_size follows it. Used
# by the HF-parity tokenizer test; weights stay tiny either way.
TOK_DIR = sys.argv[2] if len(sys.argv) > 2 else None

# tiny llada2_moe: layer 0 dense, layer 1 MoE
CFG = {
    "architectures": ["LLaDA2MoeModelLM"],
    "model_type": "llada2_moe",
    "hidden_size": 64,
    "num_hidden_layers": 2,
    "num_attention_heads": 4,
    "num_key_value_heads": 2,
    "head_dim": 16,
    "intermediate_size": 128,
    "moe_intermediate_size": 32,
    "num_experts": 8,
    "num_experts_per_tok": 2,
    "n_group": 2,
    "topk_group": 1,
    "num_shared_experts": 1,
    "first_k_dense_replace": 1,
    "max_position_embeddings": 512,
    "rms_norm_eps": 1e-6,
    "rope_theta": 600000,
    "partial_rotary_factor": 0.5,
    "routed_scaling_factor": 2.5,
    "norm_topk_prob": True,
    "score_function": "sigmoid",
    "vocab_size": 320,
    "pad_token_id": 296,
    "tie_word_embeddings": False,
}

if TOK_DIR:
    tj = json.load(open(f"{TOK_DIR}/tokenizer.json"))
    max_id = max(
        max(tj["model"]["vocab"].values()),
        max((a["id"] for a in tj.get("added_tokens", [])), default=0),
    )
    tc = json.load(open(f"{TOK_DIR}/tokenizer_config.json"))
    eos = tc.get("eos_token")
    eos_id = next((a["id"] for a in tj.get("added_tokens", []) if a["content"] == eos), None)
    CFG["vocab_size"] = max_id + 1 + 31  # pad like the real config does
    if eos_id is not None:
        CFG["pad_token_id"] = eos_id

H = CFG["hidden_size"]
NH = CFG["num_attention_heads"]
NKV = CFG["num_key_value_heads"]
HD = CFG["head_dim"]
FF = CFG["intermediate_size"]
MFF = CFG["moe_intermediate_size"]
NE = CFG["num_experts"]
NL = CFG["num_hidden_layers"]
V = CFG["vocab_size"]

rng = np.random.default_rng(42)


def t(shape):
    return (rng.standard_normal(shape) * 0.05).astype(np.float32)


tensors = {}
tensors["model.word_embeddings.weight"] = t((V, H))
tensors["lm_head.weight"] = t((V, H))
tensors["model.norm.weight"] = t((H,)) + 1.0
for L in range(NL):
    p = f"model.layers.{L}."
    tensors[p + "input_layernorm.weight"] = t((H,)) + 1.0
    tensors[p + "attention.query_key_value.weight"] = t(((NH + 2 * NKV) * HD, H))
    tensors[p + "attention.query_layernorm.weight"] = t((HD,)) + 1.0
    tensors[p + "attention.key_layernorm.weight"] = t((HD,)) + 1.0
    tensors[p + "attention.dense.weight"] = t((H, NH * HD))
    tensors[p + "post_attention_layernorm.weight"] = t((H,)) + 1.0
    if L < CFG["first_k_dense_replace"]:
        tensors[p + "mlp.gate_proj.weight"] = t((FF, H))
        tensors[p + "mlp.up_proj.weight"] = t((FF, H))
        tensors[p + "mlp.down_proj.weight"] = t((H, FF))
    else:
        tensors[p + "mlp.gate.weight"] = t((NE, H))
        tensors[p + "mlp.gate.expert_bias"] = t((NE,))
        for e in range(NE):
            ep = f"{p}mlp.experts.{e}."
            tensors[ep + "gate_proj.weight"] = t((MFF, H))
            tensors[ep + "up_proj.weight"] = t((MFF, H))
            tensors[ep + "down_proj.weight"] = t((H, MFF))
        tensors[p + "mlp.shared_experts.gate_proj.weight"] = t((MFF, H))
        tensors[p + "mlp.shared_experts.up_proj.weight"] = t((MFF, H))
        tensors[p + "mlp.shared_experts.down_proj.weight"] = t((H, MFF))


def f32_to_bf16_bytes(a):
    # round-to-nearest-even truncation of the low 16 bits
    bits = a.astype(np.float32).view(np.uint32)
    rounded = (bits + 0x7FFF + ((bits >> 16) & 1)).astype(np.uint32)
    return (rounded >> 16).astype(np.uint16).tobytes()


def write_shard(path, names, bf16_names):
    header = {}
    off = 0
    blobs = []
    for n in names:
        a = tensors[n]
        if n in bf16_names:
            data = f32_to_bf16_bytes(a)
            dt = "BF16"
        else:
            data = a.tobytes()
            dt = "F32"
        header[n] = {
            "dtype": dt,
            "shape": list(a.shape),
            "data_offsets": [off, off + len(data)],
        }
        off += len(data)
        blobs.append(data)
    hj = json.dumps(header).encode()
    pad = (8 - len(hj) % 8) % 8
    hj += b" " * pad
    with open(path, "wb") as f:
        f.write(struct.pack("<Q", len(hj)))
        f.write(hj)
        for b in blobs:
            f.write(b)


names = sorted(tensors.keys())
half = len(names) // 2
# the embedding goes through the BF16 path to prove the dtype widening
bf16_names = {"model.word_embeddings.weight"}
write_shard(f"{OUT}/model-00000-of-00002.safetensors", names[:half], bf16_names)
write_shard(f"{OUT}/model-00001-of-00002.safetensors", names[half:], bf16_names)

with open(f"{OUT}/config.json", "w") as f:
    json.dump(CFG, f, indent=1)

if TOK_DIR:
    shutil.copy(f"{TOK_DIR}/tokenizer.json", f"{OUT}/tokenizer.json")
    shutil.copy(f"{TOK_DIR}/tokenizer_config.json", f"{OUT}/tokenizer_config.json")
    for n in names:
        print("TENSOR", n, ",".join(str(x) for x in tensors[n].shape))
    np.save(f"{OUT}/source_tensors.npy", tensors, allow_pickle=True)
    sys.exit(0)

# ── a miniature byte-level BPE tokenizer.json ──
# base vocab: the 256 byte-level unicode remap chars would be the real
# thing; a handful of printable tokens is enough for the converter,
# which copies strings verbatim.
vocab = {}
for i in range(290):
    vocab[f"tok{i}"] = i
merges = ["t ok", "to k"]
added = [
    {"id": 295, "content": "<|startoftext|>", "single_word": False, "lstrip": False,
     "rstrip": False, "normalized": False, "special": True},
    {"id": 296, "content": "<|endoftext|>", "single_word": False, "lstrip": False,
     "rstrip": False, "normalized": False, "special": True},
    {"id": 297, "content": "<|mask|>", "single_word": False, "lstrip": False,
     "rstrip": False, "normalized": False, "special": True},
    {"id": 298, "content": "<userdef>", "single_word": False, "lstrip": False,
     "rstrip": False, "normalized": False, "special": False},
]
tok = {
    "version": "1.0",
    "added_tokens": added,
    "normalizer": {"type": "NFC"},
    "pre_tokenizer": {"type": "ByteLevel", "add_prefix_space": False},
    "model": {"type": "BPE", "vocab": vocab, "merges": merges},
}
with open(f"{OUT}/tokenizer.json", "w") as f:
    json.dump(tok, f)

with open(f"{OUT}/tokenizer_config.json", "w") as f:
    json.dump({
        "add_bos_token": False,
        "add_eos_token": False,
        "bos_token": "<|startoftext|>",
        "eos_token": "<|endoftext|>",
        "chat_template": "{{ '<role>HUMAN</role>' }}",
    }, f)

for n in names:
    print("TENSOR", n, ",".join(str(x) for x in tensors[n].shape))
np.save(f"{OUT}/source_tensors.npy", tensors, allow_pickle=True)
