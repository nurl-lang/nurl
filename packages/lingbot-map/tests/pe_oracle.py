#!/usr/bin/env python3
"""torch Conv2d(c, nout, patch, stride=patch) over the same inputs
tests/pecheck.nu builds — the reference for src/patchembed.nu. The
output is flattened as [P, nout] with P in row-major patch order, which
is `flatten(2).transpose(1,2)` on Conv2d's [nout, gh, gw]."""
import math

import torch


def case(c, h, w, patch, nout):
    k = c * patch * patch
    img = torch.tensor([math.sin(0.3 + 0.017 * j) for j in range(c * h * w)],
                       dtype=torch.float64).reshape(1, c, h, w)
    wgt = torch.tensor([math.cos(0.7 + 0.011 * j) for j in range(nout * k)],
                       dtype=torch.float64).reshape(nout, c, patch, patch)
    bia = torch.tensor([0.01 * (j - 2) for j in range(nout)], dtype=torch.float64)
    y = torch.nn.functional.conv2d(img, wgt, bia, stride=patch)
    y = y.flatten(2).transpose(1, 2).reshape(-1)
    fmt = lambda v: str(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v)
    print("p%d_%d_%d_%d_%d %s" % (c, h, w, patch, nout,
                                  " ".join(fmt(v) for v in y.tolist())))


def main():
    case(3, 28, 42, 14, 5)
    case(3, 14, 14, 14, 4)
    case(2, 12, 8, 4, 6)


if __name__ == "__main__":
    main()
