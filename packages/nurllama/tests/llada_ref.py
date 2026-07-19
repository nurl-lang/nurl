#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/llada_ref.py — an INDEPENDENT numpy implementation of the
#  llada2 (LLaDA2.x MoE diffusion) forward pass, reading the crafted
#  checkpoint's config.json + source_tensors.npy directly. No code is
#  shared with the NURL side; this is the oracle `nurllama dlogits`
#  is compared against.
#
#  Usage: llada_ref.py <hf-dir> <id> [id ...]
#  Prints one line per position: every logit, space-separated.
#
#  The whole id sequence is ONE bidirectional window (positions 0..n-1,
#  every query sees every position) — the same semantics as
#  `nurllama dlogits`.
# ============================================================
import json
import sys

import numpy as np

def load(d):
    cfg = json.load(open(f"{d}/config.json"))
    T = np.load(f"{d}/source_tensors.npy", allow_pickle=True).item()
    return cfg, T


def forward(cfg, T, ids, block_len=None):
    """Logits for every position. block_len=None → fully bidirectional
    (one window); an int applies the block-diffusion mask: position q
    attends k iff block(k) <= block(q)."""
    H = cfg["hidden_size"]
    NH = cfg["num_attention_heads"]
    NKV = cfg["num_key_value_heads"]
    HD = cfg["head_dim"]
    NL = cfg["num_hidden_layers"]
    NE = cfg["num_experts"]
    TOPK = cfg["num_experts_per_tok"]
    NG = cfg["n_group"]
    TOPG = cfg["topk_group"]
    EPS = cfg["rms_norm_eps"]
    BASE = cfg["rope_theta"]
    RD = int(HD * cfg.get("partial_rotary_factor", 1.0))
    SCALE = cfg["routed_scaling_factor"]
    FIRST_DENSE = cfg["first_k_dense_replace"]

    def rms(x, w):
        v = np.sqrt((x * x).mean(-1, keepdims=True) + EPS)
        return x / v * w

    def rope(x, pos):
        inv = 1.0 / (BASE ** (np.arange(0, RD, 2) / RD))
        freqs = np.outer(pos, inv)
        emb = np.concatenate([freqs, freqs], axis=-1)
        cos = np.cos(emb)[:, None, :]
        sin = np.sin(emb)[:, None, :]
        rot, rest = x[..., :RD], x[..., RD:]
        rot = rot * cos + rotate_half(rot) * sin
        return np.concatenate([rot, rest], axis=-1)

    n = len(ids)
    x = bf16_rne(T["model.word_embeddings.weight"])[ids]
    pos = np.arange(n)
    if block_len is None:
        amask = np.zeros((n, n))
    else:
        blk = pos // block_len
        amask = np.where(blk[None, :] > blk[:, None], -np.inf, 0.0)
    for L in range(NL):
        p = f"model.layers.{L}."
        h = rms(x, T[p + "input_layernorm.weight"].astype(np.float64))
        qkv = h @ T[p + "attention.query_key_value.weight"].astype(np.float64).T
        q = qkv[:, : NH * HD].reshape(n, NH, HD)
        k = qkv[:, NH * HD : (NH + NKV) * HD].reshape(n, NKV, HD)
        v = qkv[:, (NH + NKV) * HD :].reshape(n, NKV, HD)
        q = rms(q, T[p + "attention.query_layernorm.weight"].astype(np.float64))
        k = rms(k, T[p + "attention.key_layernorm.weight"].astype(np.float64))
        q = rope(q, pos)
        k = rope(k, pos)
        rep = NH // NKV
        kf = np.repeat(k, rep, axis=1)
        vf = np.repeat(v, rep, axis=1)
        att = np.einsum("qhd,khd->hqk", q, kf) / np.sqrt(HD) + amask[None, :, :]
        att = att - att.max(-1, keepdims=True)
        att = np.exp(att)
        att = att / att.sum(-1, keepdims=True)
        out = np.einsum("hqk,khd->qhd", att, vf).reshape(n, NH * HD)
        x = x + out @ T[p + "attention.dense.weight"].astype(np.float64).T

        h = rms(x, T[p + "post_attention_layernorm.weight"].astype(np.float64))
        if L < FIRST_DENSE:
            g = silu(h @ T[p + "mlp.gate_proj.weight"].astype(np.float64).T)
            u = h @ T[p + "mlp.up_proj.weight"].astype(np.float64).T
            x = x + (g * u) @ T[p + "mlp.down_proj.weight"].astype(np.float64).T
        else:
            g = silu(h @ T[p + "mlp.shared_experts.gate_proj.weight"].astype(np.float64).T)
            u = h @ T[p + "mlp.shared_experts.up_proj.weight"].astype(np.float64).T
            ffn = (g * u) @ T[p + "mlp.shared_experts.down_proj.weight"].astype(np.float64).T
            logits = h @ T[p + "mlp.gate.weight"].astype(np.float64).T
            scores = 1.0 / (1.0 + np.exp(-logits))
            biased = scores + T[p + "mlp.gate.expert_bias"].astype(np.float64)
            per = NE // NG
            for t in range(n):
                gsc = np.sort(biased[t].reshape(NG, per), axis=-1)[:, -2:].sum(-1)
                keep = np.argsort(-gsc)[:TOPG]
                mask = np.full(NE, -np.inf)
                for gidx in keep:
                    mask[gidx * per : (gidx + 1) * per] = 0.0
                sel = np.argsort(-(biased[t] + mask))[:TOPK]
                w = scores[t][sel]
                if cfg.get("norm_topk_prob", True):
                    w = w / (w.sum() + 1e-20)
                w = w * SCALE
                acc = np.zeros(H)
                for e, we in zip(sel, w):
                    ep = f"{p}mlp.experts.{e}."
                    ge = silu(h[t] @ T[ep + "gate_proj.weight"].astype(np.float64).T)
                    ue = h[t] @ T[ep + "up_proj.weight"].astype(np.float64).T
                    acc += we * ((ge * ue) @ T[ep + "down_proj.weight"].astype(np.float64).T)
                ffn[t] += acc
            x = x + ffn

    x = rms(x, T["model.norm.weight"].astype(np.float64))
    return x @ T["lm_head.weight"].astype(np.float64).T


def bf16_rne(a):
    bits = a.astype(np.float32).view(np.uint32)
    rounded = (bits + 0x7FFF + ((bits >> 16) & 1)).astype(np.uint32)
    return ((rounded >> 16).astype(np.uint32) << 16).view(np.float32).astype(np.float64)


def rotate_half(x):
    h = x.shape[-1] // 2
    return np.concatenate([-x[..., h:], x[..., :h]], axis=-1)


def silu(x):
    return x / (1.0 + np.exp(-x))


if __name__ == "__main__":
    d = sys.argv[1]
    ids = [int(x) for x in sys.argv[2:]]
    cfg, T = load(d)
    logits = forward(cfg, T, ids)
    for row in logits:
        print(" ".join("%.6g" % v for v in row))
