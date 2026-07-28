#!/usr/bin/env python3
"""The reference's own preprocessing over synthetic PNGs, printed as bytes.

Drives the upstream functions themselves — find_closest_aspect_ratio and
crop_resize_if_necessary, exactly as load_images composes them — rather
than re-implementing the math, so this file cannot drift into a second
opinion. tests/preproccheck.nu prints the same thing out of pp_*; the
test is a byte diff.

PNGs, not JPEGs, on purpose: the image package's JPEG decoder is
IDCT-close to Pillow but not byte-identical, and this test is about
preprocessing, not codecs.

Usage: preproc_oracle.py <outdir>   (writes PNGs into outdir, prints dump)
"""

import sys

import numpy as np
import PIL.Image

sys.path.insert(0, "/home/wau/dev/map-anything")
from mapanything.utils.cropping import crop_resize_if_necessary
from mapanything.utils.image import find_closest_aspect_ratio

SIZES = [(640, 480), (1024, 768), (333, 517), (2000, 1500), (518, 291)]


def make_img(w, h, seed):
    x = np.arange(w)[None, :, None]
    y = np.arange(h)[:, None, None]
    k = np.arange(3)[None, None, :]
    v = (37 * x + 61 * y + 91 * k + 13 * ((x * y) % 7) + seed) % 251
    return PIL.Image.fromarray(v.astype(np.uint8), "RGB")


def main():
    outdir = sys.argv[1]
    imgs = []
    for i, (w, h) in enumerate(SIZES):
        img = make_img(w, h, i)
        img.save(f"{outdir}/pp_{i}.png")
        imgs.append(img)

    aspect = sum(im.size[0] / im.size[1] for im in imgs) / len(imgs)
    tw, th = find_closest_aspect_ratio(aspect, 518)
    print("target %d %d" % (tw, th))

    for i, im in enumerate(imgs):
        out = crop_resize_if_necessary(im, resolution=(tw, th))[0]
        data = np.asarray(out)  # H,W,3 uint8
        print(
            "img%d %dx%d %s" % (i, out.size[0], out.size[1], " ".join(str(b) for b in data.flatten()))
        )


if __name__ == "__main__":
    main()
