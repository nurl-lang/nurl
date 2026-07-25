#!/usr/bin/env python3
"""torch reference for tests/fusecheck.nu — the has_residual=False path
of a DPT FeatureFusionBlock (refinenet4), on the same synthetic weights."""
import math

import torch
import torch.nn.functional as F

CH, H, W, OH, OW = 8, 3, 5, 6, 10


def gen(n, phase):
    return torch.tensor([0.5 * math.sin(phase + 0.037 * j) for j in range(n)],
                        dtype=torch.float64)


def conv(cout, cin, k, phase):
    return gen(cout * cin * k * k, phase).reshape(cout, cin, k, k), gen(cout, phase + 0.5)


def row(label, t):
    fmt = lambda v: str(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v)
    print("%s | %s" % (label, " ".join(fmt(v) for v in t.reshape(-1).tolist())))


def main():
    x = gen(CH * H * W, 0.11).reshape(1, CH, H, W)
    w1, b1 = conv(CH, CH, 3, 1.7)
    w2, b2 = conv(CH, CH, 3, 2.1)
    ow_, ob = conv(CH, CH, 1, 2.5)
    row("fc_in", x)
    # resConfUnit2: relu, conv, relu, conv, + input
    o = F.relu(x)
    o = F.conv2d(o, w1, b1, padding=1)
    o = F.relu(o)
    o = F.conv2d(o, w2, b2, padding=1)
    x = o + x
    row("fc_rcu", x)
    up = F.interpolate(x, size=(OH, OW), mode="bilinear", align_corners=True)
    row("fc_up", up)
    out = F.conv2d(up, ow_, ob)
    row("fc_out", out)


if __name__ == "__main__":
    main()
