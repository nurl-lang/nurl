#!/usr/bin/env python3
"""Reference preprocessing for tests/preproccheck.nu — the crop-mode path
of lingbot_map.utils.load_fn.load_and_preprocess_images, inlined so the
comparison does not need the upstream package installed (only PIL).

EXIF transposition is left out here to match the NURL side, which does not
apply it; the fixtures carry no EXIF, so the two agree by construction
rather than by luck.
"""
import sys

from PIL import Image

SIZE = 518
PATCH = 14
STRIDE = 997


def load_one(path):
    img = Image.open(path)
    if img.mode == "RGBA":
        background = Image.new("RGBA", img.size, (255, 255, 255, 255))
        img = Image.alpha_composite(background, img)
    img = img.convert("RGB")
    width, height = img.size

    new_width = SIZE
    new_height = round(height * (new_width / width) / PATCH) * PATCH
    img = img.resize((new_width, new_height), Image.Resampling.BICUBIC)

    # ToTensor(): HWC uint8 → CHW float in [0,1]
    raw = img.tobytes()
    chw = [[[raw[(y * new_width + x) * 3 + c] / 255.0
             for x in range(new_width)]
            for y in range(new_height)]
           for c in range(3)]

    if new_height > SIZE:
        start_y = (new_height - SIZE) // 2
        chw = [plane[start_y:start_y + SIZE] for plane in chw]

    h = len(chw[0])
    flat = [v for plane in chw for row in plane for v in row]
    return new_width, h, flat


def fmt(x):
    if x == int(x) and abs(x) < 1e15:
        return str(int(x))
    return repr(x)


def main():
    for path in sys.argv[1:]:
        w, h, flat = load_one(path)
        vals = flat[::STRIDE]
        print("frame %s %dx%d %s" % (path, w, h, " ".join(fmt(v) for v in vals)))


if __name__ == "__main__":
    main()
