#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/llada_dz_ref.py — the LLaDA2.1 reference DECODE loop
#  (greedy JointThreshold + editing), mirroring the HF modeling code's
#  generate(): the whole prefix is recomputed with the block-diffusion
#  attention mask on every denoise step — no caching anywhere. The
#  NURL loop (src/diffuse.nu) freezes completed blocks' K/V instead;
#  the two must nonetheless produce IDENTICAL ids, which is exactly
#  what the comparison proves.
#
#  Usage: llada_dz_ref.py <hf-dir> <gen_len> <block_len> <threshold>
#                          <edit_thr> <max_post> <mask_id> <eos_id>
#                          <prompt-id> [id ...]
#  Prints the generated ids (after the prompt, cut BEFORE the first
#  EOS), space-separated.
# ============================================================
import sys

import numpy as np

import llada_ref

d = sys.argv[1]
gen_len, block_len = int(sys.argv[2]), int(sys.argv[3])
threshold, edit_thr = float(sys.argv[4]), float(sys.argv[5])
max_post = int(sys.argv[6])
mask_id, eos_id = int(sys.argv[7]), int(sys.argv[8])
prompt = [int(x) for x in sys.argv[9:]]

cfg, T = llada_ref.load(d)

np_len = len(prompt)
nblocks = (np_len + gen_len + block_len - 1) // block_len
total = nblocks * block_len
x = np.full(total, mask_id, dtype=np.int64)
x[:np_len] = prompt

prefill = np_len // block_len
stop = False
for nb in range(prefill, nblocks):
    if stop:
        break
    bs, be = nb * block_len, (nb + 1) * block_len
    post = 0
    while True:
        active = x[bs:be] == mask_id
        if not active.any():
            post += 1
        if post > max_post:
            break
        logits = llada_ref.forward(cfg, T, list(x[:be]), block_len=block_len)[bs:be]
        x0 = logits.argmax(1)
        m = logits.max(1, keepdims=True)
        p = np.exp(logits - m)
        p = p / p.sum(1, keepdims=True)
        conf = p[np.arange(block_len), x0]
        blk = x[bs:be]
        if active.any():
            hi = active & (conf > threshold)
            if hi.any():
                blk[hi] = x0[hi]
            else:
                cm = np.where(active, conf, -np.inf)
                blk[cm.argmax()] = x0[cm.argmax()]
        edited = False
        editable = (~active) & (np.arange(bs, be) >= np_len)
        for i in range(block_len):
            if editable[i] and conf[i] > edit_thr and x0[i] != blk[i]:
                blk[i] = x0[i]
                edited = True
        if not active.any() and not edited:
            break
    gen = x[np_len:be]
    if (gen != mask_id).all() and (gen == eos_id).any():
        stop = True

out = []
for id_ in x[np_len : np_len + gen_len]:
    if id_ == eos_id:
        break
    out.append(int(id_))
print(" ".join(str(i) for i in out))
