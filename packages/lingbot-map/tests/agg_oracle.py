#!/usr/bin/env python3
"""Ground truth for stages 4-5, straight from the real model.

Builds GCTStream exactly as demo.py does (enable_3d_rope on, SDPA KV
cache), loads the real checkpoint, preprocesses one example frame with
the reference loader, and dumps a deterministic sample of every
intermediate the port has to reproduce.

  agg_oracle.py <checkpoint.pt> <frame.png> [frame.png ...]

Sampling, not full dumps: a 783x1024 tensor is 800k numbers per layer.
A prime stride walks all of it without printing all of it, and any
structural error (a transposed axis, a dropped token) moves every
sample.
"""
import os
import sys

import torch

sys.path.insert(0, os.path.expanduser("~/dev/lingbot-map"))
torch.set_grad_enabled(False)

from lingbot_map.models.gct_stream import GCTStream          # noqa: E402
from lingbot_map.utils.load_fn import load_and_preprocess_images  # noqa: E402

STRIDE = 9973


def fmt(v):
    v = float(v)
    return str(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v)


def dump(label, t):
    flat = t.reshape(-1).to(torch.float64)
    vals = flat[::STRIDE].tolist()
    print("%s %s | %s" % (label, "x".join(str(d) for d in t.shape),
                          " ".join(fmt(v) for v in vals)))


def main():
    ckpt_path, frames = sys.argv[1], sys.argv[2:]
    model = GCTStream(img_size=518, patch_size=14, enable_3d_rope=True,
                      max_frame_num=1024, kv_cache_sliding_window=64,
                      kv_cache_scale_frames=8, kv_cache_cross_frame_special=True,
                      kv_cache_include_scale_frames=True, use_sdpa=True,
                      camera_num_iterations=4)
    ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    sd = ckpt.get("model", ckpt)
    missing, unexpected = model.load_state_dict(sd, strict=False)
    print("missing %d unexpected %d" % (len(missing), len(unexpected)))
    model.eval()

    images = load_and_preprocess_images(frames, image_size=518, patch_size=14)
    dump("input", images)

    agg = model.aggregator
    B, S = 1, images.shape[0]
    imgs = images.unsqueeze(0)

    # what the aggregator normalises to
    norm = (imgs - agg._resnet_mean) / agg._resnet_std
    dump("normalised", norm)

    # DINOv2 patch tokens — the aggregator's actual entry point
    flat = norm.view(B * S, *norm.shape[2:])
    pt = agg.patch_embed(flat)
    if isinstance(pt, dict):
        pt = pt["x_norm_patchtokens"]
    dump("dino_patchtokens", pt)

    outs, psi = agg(imgs, selected_idx=[4, 11, 17, 23])
    print("patch_start_idx %d outputs %d" % (psi, len(outs)))
    for i, o in enumerate(outs):
        dump("agg_out_%d" % i, o)


if __name__ == "__main__":
    main()
