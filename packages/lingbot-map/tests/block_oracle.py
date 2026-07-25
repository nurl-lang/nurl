#!/usr/bin/env python3
"""The reference transformer Block (lingbot_map.layers.block.Block with
qk_norm=True, init_values set, 2-D RoPE), inlined in torch so the
comparison needs no upstream install. Same deterministic weights as
tests/blockcheck.nu."""
import math

import torch
import torch.nn.functional as F


def gen(n, phase):
    return torch.tensor([0.3 * math.sin(phase + 0.019 * j) for j in range(n)],
                        dtype=torch.float64)


def genpos(n, phase, base):
    return torch.tensor([base + 0.1 * math.sin(phase + 0.023 * j) for j in range(n)],
                        dtype=torch.float64)


def freq_components(dim, seq_len, base=100.0):
    exponents = torch.arange(0, dim, 2, dtype=torch.float64) / dim
    inv_freq = 1.0 / (base ** exponents)
    positions = torch.arange(seq_len, dtype=torch.float64)
    angles = torch.einsum("i,j->ij", positions, inv_freq)
    angles = torch.cat((angles, angles), dim=-1)
    return angles.cos(), angles.sin()


def rotate(x):
    d = x.shape[-1]
    return torch.cat((-x[..., d // 2:], x[..., : d // 2]), dim=-1)


def rope(tokens, positions, maxpos):
    fd = tokens.shape[-1] // 2
    cos_c, sin_c = freq_components(fd, maxpos)
    vert, horiz = tokens.chunk(2, dim=-1)

    def ap(t, p):
        cos = F.embedding(p, cos_c)[:, None, :, :]
        sin = F.embedding(p, sin_c)[:, None, :, :]
        return t * cos + rotate(t) * sin

    return torch.cat((ap(vert, positions[..., 0]), ap(horiz, positions[..., 1])), dim=-1)


def case(gw, gh, nspecial, dim, heads, hidden):
    n = nspecial + gw * gh
    hd = dim // heads
    x = gen(n * dim, 0.11).reshape(1, n, dim)
    n1g, n1b = genpos(dim, 0.2, 1.0), gen(dim, 0.3)
    qw = gen(3 * dim * dim, 0.4).reshape(3 * dim, dim)
    qb = gen(3 * dim, 0.5)
    qng, qnb = genpos(hd, 0.6, 1.0), gen(hd, 0.7)
    kng, knb = genpos(hd, 0.8, 1.0), gen(hd, 0.9)
    pw = gen(dim * dim, 1.0).reshape(dim, dim)
    pb = gen(dim, 1.1)
    ls1 = genpos(dim, 1.2, 0.05)
    n2g, n2b = genpos(dim, 1.3, 1.0), gen(dim, 1.4)
    f1w = gen(hidden * dim, 1.5).reshape(hidden, dim)
    f1b = gen(hidden, 1.6)
    f2w = gen(dim * hidden, 1.7).reshape(dim, hidden)
    f2b = gen(dim, 1.8)
    ls2 = genpos(dim, 1.9, 0.05)

    pos = torch.zeros(1, n, 2, dtype=torch.long)
    for y in range(gh):
        for xx in range(gw):
            i = nspecial + y * gw + xx
            pos[0, i, 0] = y + 1
            pos[0, i, 1] = xx + 1
    maxpos = max(gw, gh) + 2

    # Block builds Attention WITHOUT passing norm_layer, so norm1/norm2 get
    # DINOv2's partial(LayerNorm, eps=1e-6) while q_norm/k_norm fall back to
    # nn.LayerNorm's own default of 1e-5. Two different epsilons, and the
    # port has to carry both.
    eps, qk_eps = 1e-6, 1e-5
    h = F.layer_norm(x, (dim,), n1g, n1b, eps)
    qkv = F.linear(h, qw, qb).reshape(1, n, 3, heads, hd).permute(2, 0, 3, 1, 4)
    q, k, v = qkv.unbind(0)
    q = F.layer_norm(q, (hd,), qng, qnb, qk_eps)
    k = F.layer_norm(k, (hd,), kng, knb, qk_eps)
    q = rope(q, pos, maxpos)
    k = rope(k, pos, maxpos)
    a = F.scaled_dot_product_attention(q, k, v)
    a = a.transpose(1, 2).reshape(1, n, dim)
    a = F.linear(a, pw, pb)
    x = x + ls1 * a

    h = F.layer_norm(x, (dim,), n2g, n2b, eps)
    h = F.gelu(F.linear(h, f1w, f1b))
    h = F.linear(h, f2w, f2b)
    x = x + ls2 * h

    fmt = lambda v: str(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v)
    print("b%d_%d_%d_%d_%d_%d %s" % (gw, gh, nspecial, dim, heads, hidden,
                                     " ".join(fmt(v) for v in x.reshape(-1).tolist())))


def main():
    case(3, 2, 1, 16, 2, 32)
    case(4, 3, 6, 32, 4, 64)


if __name__ == "__main__":
    main()
