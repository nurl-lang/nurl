#!/usr/bin/env python3
"""torch's bicubic+antialias resample over the same grids
tests/interpcheck.nu builds — the reference for interp_bicubic_aa, which
is what DINOv2's position-embedding resample runs on."""
import math

import torch
import torch.nn.functional as F


def fill(sw, sh, planes):
    t = torch.zeros(1, planes, sh, sw, dtype=torch.float64)
    for c in range(planes):
        for y in range(sh):
            for x in range(sw):
                t[0, c, y, x] = (math.sin(6.2831853 * (x / sw))
                                 + math.cos(4.1887902 * (y / sh))
                                 + 0.25 * c)
    return t


def fmt(v):
    return str(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v)


def case(sw, sh, planes, dw, dh):
    src = fill(sw, sh, planes)
    out = F.interpolate(src, size=(dh, dw), mode="bicubic",
                        antialias=True, align_corners=False)
    vals = out.reshape(-1).tolist()
    print("g%d_%d_%d_%d_%d %s" % (sw, sh, planes, dw, dh,
                                  " ".join(fmt(v) for v in vals)))


def main():
    case(37, 37, 2, 37, 21)
    case(37, 37, 1, 37, 37)
    case(37, 37, 1, 11, 9)
    case(8, 8, 2, 19, 23)
    case(16, 4, 1, 5, 13)


if __name__ == "__main__":
    main()
