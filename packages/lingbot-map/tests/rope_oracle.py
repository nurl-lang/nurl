#!/usr/bin/env python3
"""Reference 2-D RoPE, from lingbot_map.layers.rope.RotaryPositionEmbedding2D
(frequency 100), over the same tensors tests/ropecheck.nu builds."""
import math

import torch
import torch.nn.functional as F


def freq_components(dim, seq_len, base=100.0):
    exponents = torch.arange(0, dim, 2, dtype=torch.float64) / dim
    inv_freq = 1.0 / (base ** exponents)
    positions = torch.arange(seq_len, dtype=torch.float64)
    angles = torch.einsum("i,j->ij", positions, inv_freq)
    angles = torch.cat((angles, angles), dim=-1)
    return angles.cos(), angles.sin()


def rotate(x):
    d = x.shape[-1]
    x1, x2 = x[..., : d // 2], x[..., d // 2:]
    return torch.cat((-x2, x1), dim=-1)


def apply_1d(tokens, positions, cos_c, sin_c):
    cos = F.embedding(positions, cos_c)[:, None, :, :]
    sin = F.embedding(positions, sin_c)[:, None, :, :]
    return tokens * cos + rotate(tokens) * sin


def case(heads, gw, gh, dim, nspecial):
    n = nspecial + gw * gh
    x = torch.zeros(1, heads, n, dim, dtype=torch.float64)
    for h in range(heads):
        for t in range(n):
            for d in range(dim):
                x[0, h, t, d] = math.sin(0.11 + 0.37 * (h * 1000 + t * 7 + d))
    pos = torch.zeros(1, n, 2, dtype=torch.long)
    for y in range(gh):
        for xx in range(gw):
            i = nspecial + y * gw + xx
            pos[0, i, 0] = y + 1
            pos[0, i, 1] = xx + 1
    cos_c, sin_c = freq_components(dim // 2, max(gw, gh) + 2)
    vert, horiz = x.chunk(2, dim=-1)
    vert = apply_1d(vert, pos[..., 0], cos_c, sin_c)
    horiz = apply_1d(horiz, pos[..., 1], cos_c, sin_c)
    out = torch.cat((vert, horiz), dim=-1)
    fmt = lambda v: str(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v)
    print("r%d_%d_%d_%d_%d %s" % (heads, gw, gh, dim, nspecial,
                                  " ".join(fmt(v) for v in out.reshape(-1).tolist())))


def main():
    case(2, 3, 2, 8, 1)
    case(1, 4, 4, 16, 6)
    case(3, 5, 2, 8, 0)


if __name__ == "__main__":
    main()
