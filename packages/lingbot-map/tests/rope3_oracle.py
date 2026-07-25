#!/usr/bin/env python3
"""Reference 3-D rope: the real WanRotaryPosEmbed and apply_rotary_emb
from lingbot_map.layers.rope, over the same tensors rope3check.nu builds."""
import math
import os
import sys

import torch

sys.path.insert(0, os.path.expanduser("~/dev/lingbot-map"))
from lingbot_map.layers.rope import WanRotaryPosEmbed, apply_rotary_emb  # noqa: E402

PSI = 6


def case(heads, ppf, pph, ppw, fstart):
    per = PSI + pph * ppw
    n = ppf * per
    dim = 64
    x = torch.tensor([math.sin(0.13 + 0.017 * j) for j in range(heads * n * dim)],
                     dtype=torch.float64).reshape(1, heads, n, dim)
    rope = WanRotaryPosEmbed(attention_head_dim=64, patch_size=(1, 1, 1),
                             max_seq_len=1024, theta=10000.0, fhw_dim=[20, 22, 22])
    freqs = rope(ppf, pph, ppw, PSI, torch.device("cpu"),
                 f_start=fstart, f_end=fstart + ppf)
    out = apply_rotary_emb(x, freqs)
    fmt = lambda v: str(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v)
    print("w%d_%d_%d_%d_%d %s" % (heads, ppf, pph, ppw, fstart,
                                  " ".join(fmt(v) for v in out.reshape(-1).tolist())))


def main():
    case(2, 1, 3, 4, 0)
    case(1, 3, 2, 2, 0)
    case(2, 2, 3, 2, 7)


if __name__ == "__main__":
    main()
