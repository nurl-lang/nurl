#!/usr/bin/env python3
"""Pillow's bicubic resize over the same rasters tests/bicubic_check.nu
builds, printed in the same format. A byte diff of the two outputs is the
test for image_resize_bicubic.

No alpha-carrying cases here: Pillow premultiplies alpha before
resampling LA/RGBA, image_resize_bicubic resamples channels
independently, and that difference is deliberate and documented."""
from PIL import Image


def make_src(w, h, ch):
    px = bytearray()
    for y in range(h):
        for x in range(w):
            for k in range(ch):
                px.append((37 * x + 61 * y + 91 * k + 13 * ((x * y) % 7)) % 251)
    mode = {1: "L", 2: "LA", 3: "RGB", 4: "RGBA"}[ch]
    return Image.frombytes(mode, (w, h), bytes(px))


def case(w, h, ch, nw, nh, resample=Image.Resampling.BICUBIC, prefix="r"):
    src = make_src(w, h, ch)
    out = src.resize((nw, nh), resample)
    data = out.tobytes()
    label = "%s%d_%d_%d_%d_%d" % (prefix, w, h, ch, nw, nh)
    print("%s %dx%dx%d %s" % (label, nw, nh, ch, " ".join(str(b) for b in data)))


def lcase(w, h, ch, nw, nh):
    case(w, h, ch, nw, nh, Image.Resampling.LANCZOS, "l")


def main():
    case(16, 12, 3, 8, 6)
    case(16, 12, 3, 32, 24)
    case(17, 13, 3, 11, 7)
    case(17, 13, 3, 23, 29)
    case(17, 13, 3, 23, 7)
    case(20, 20, 1, 7, 7)
    case(9, 9, 3, 1, 1)
    case(1, 1, 3, 5, 5)
    case(31, 5, 3, 5, 31)
    lcase(16, 12, 3, 8, 6)
    lcase(16, 12, 3, 32, 24)
    lcase(17, 13, 3, 11, 7)
    lcase(17, 13, 3, 23, 29)
    lcase(17, 13, 3, 23, 7)
    lcase(20, 20, 1, 7, 7)
    lcase(9, 9, 3, 1, 1)
    lcase(1, 1, 3, 5, 5)
    lcase(31, 5, 3, 5, 31)
    lcase(200, 150, 3, 74, 56)


if __name__ == "__main__":
    main()
