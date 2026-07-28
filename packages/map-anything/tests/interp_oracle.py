#!/usr/bin/env python3
"""torch's upsample_bicubic2d over the same grids tests/interpcheck.nu
builds, with DINOv2's scale_factor kludge. Printed as %g floats; the
comparison is numeric (oracle f32 vs port f64), gate 1e-5."""

import numpy as np
import torch
import torch.nn.functional as F

M, C = 37, 3


def make_grid():
    p = np.arange(M * M)[None, :]
    k = np.arange(C)[:, None]
    v = (37 * p + 91 * k + 13 * ((p * k) % 7)) % 251
    return (v / 251.0).astype(np.float32).reshape(1, C, M, M)


def case(oh, ow):
    x = torch.from_numpy(make_grid())
    sy = float(oh + 0.1) / M
    sx = float(ow + 0.1) / M
    out = F.interpolate(x, mode="bicubic", antialias=False, scale_factor=(sy, sx))
    assert out.shape[-2:] == (oh, ow), out.shape
    vals = out.numpy().flatten()
    print("case %d %d %s" % (oh, ow, " ".join("%g" % v for v in vals)))


def main():
    case(28, 37)
    case(37, 28)
    case(21, 37)
    case(12, 37)
    case(40, 40)


if __name__ == "__main__":
    main()
