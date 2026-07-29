#!/usr/bin/env python3
"""The reference sky mask over one preprocessed view.

Preprocesses <image> exactly as the port does (the reference's own
load_images), denormalises, runs the LingBot demo's segment_sky_from_array
with onnxruntime, and writes the keep-mask as u8 (1 = not sky).

Usage: sky_oracle.py <image> <skyseg.onnx> <out_mask.bin>
"""

import sys

import numpy as np
import onnxruntime

sys.path.insert(0, "/home/wau/dev/lingbot-map")
from lingbot_map.vis.sky_segmentation import _SKYSEG_SOFT_THRESHOLD, segment_sky_from_array

from mapanything.utils.image import load_images


def main():
    img_path, model_path, out_path = sys.argv[1:4]
    views = load_images([img_path])
    img = views[0]["img"][0].numpy()  # [3,H,W] normalised
    mean = np.array([0.485, 0.456, 0.406], np.float32)[:, None, None]
    std = np.array([0.229, 0.224, 0.225], np.float32)[:, None, None]
    rgb01 = np.clip(img * std + mean, 0, 1)
    sess = onnxruntime.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    h, w = rgb01.shape[1:]
    nonsky = segment_sky_from_array(rgb01, sess, h, w)
    keep = (nonsky > _SKYSEG_SOFT_THRESHOLD).astype(np.uint8)
    keep.tofile(out_path)
    print("shape %dx%d kept %.2f%%" % (w, h, keep.mean() * 100))


if __name__ == "__main__":
    main()
