#!/usr/bin/env python3
"""The REFERENCE, writing the same point cloud `lingbot-map` writes.

  ref_cloud.py <checkpoint.pt> <out.ply> <frame.png> ...
      [--conf F] [--pixel-stride N] [--dtype float32|bf16]

This exists so that "the port behaves exactly like ~/dev/lingbot-map, but
faster" is a number rather than a claim. `tests/ref_timing.py` compares
one frame of three modules; this compares the actual deliverable — every
frame, every point, and the wall clock around the whole run.

The model is built exactly as `demo.py` builds it (streaming mode,
enable_3d_rope, 8 scale frames, a 64-frame sliding window, 4 camera
iterations) and driven through the same `inference_streaming`. The cloud
is then assembled the way `main.nu` assembles it: keep pixels whose
`depth_conf` exceeds --conf, take every --pixel-stride-th pixel on both
axes, unproject with the reference's own
`unproject_depth_map_to_point_map`, and write binary_little_endian PLY
with the same property order.

Two conventions are load-bearing and are the reference's, not choices
made here: the pixel grid is integer coordinates (np.arange, not sample
centres), and the unprojection takes the WORLD-FROM-CAMERA extrinsic and
inverts it itself.

Timing is reported on stderr as `ref_seconds <total> <load> <inference>`
so a caller can compare it against the port's own total.
"""
import os
import struct
import sys
import time

import numpy as np
import torch

sys.path.insert(0, os.path.expanduser("~/dev/lingbot-map"))
torch.set_grad_enabled(False)

from lingbot_map.models.gct_stream import GCTStream               # noqa: E402
from lingbot_map.utils.load_fn import load_and_preprocess_images   # noqa: E402
from lingbot_map.utils.pose_enc import pose_encoding_to_extri_intri  # noqa: E402
from lingbot_map.utils.geometry import (                          # noqa: E402
    unproject_depth_map_to_point_map,
)

DTYPES = {"float32": torch.float32, "fp32": torch.float32,
          "bfloat16": torch.bfloat16, "bf16": torch.bfloat16}


def main():
    args = sys.argv[1:]
    conf_thr, pixel_stride, dtype, scale_frames = 1.5, 2, torch.float32, 8
    jitter = 0.0
    image_size = 518
    rest = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--conf":
            conf_thr = float(args[i + 1]); i += 2
        elif a == "--pixel-stride":
            pixel_stride = int(args[i + 1]); i += 2
        elif a == "--dtype":
            dtype = DTYPES[args[i + 1]]; i += 2
        elif a == "--jitter":
            # Perturb the preprocessed frames by this RELATIVE amount before
            # inference. The point is to measure the reference's sensitivity
            # to a disturbance the size of the port's own f32 disagreement:
            # if the reference moves as far when nudged by 1e-6 as the port
            # sits from it, the two are as close as this model allows, and
            # the gap is the system's conditioning rather than a porting bug.
            jitter = float(args[i + 1]); i += 2
        elif a == "--image-size":
            image_size = int(args[i + 1]); i += 2
        elif a == "--scale-frames":
            # inference_streaming's Phase 1 batch size. demo.py's default
            # is 8, which gives those frames BIDIRECTIONAL attention among
            # themselves; 1 makes every frame causal, which is how the port
            # drives the model. This is the one behavioural axis on which
            # the two can legitimately disagree.
            scale_frames = int(args[i + 1]); i += 2
        else:
            rest.append(a); i += 1
    ckpt_path, out_path, frames = rest[0], rest[1], rest[2:]
    if not frames:
        sys.exit("ref_cloud.py: no frames")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    cuda = device.type == "cuda"

    def sync():
        if cuda:
            torch.cuda.synchronize()

    t_total0 = time.time()

    # img_size stays 518 whatever --image-size says: the checkpoint's
    # pos_embed is 1370 rows and load_state_dict rejects any other build
    # size. Other input sizes are handled at RUNTIME by
    # interpolate_pos_encoding — which is also exactly how the port does
    # it, so the two stay comparable.
    model = GCTStream(img_size=518, patch_size=14, enable_3d_rope=True,
                      max_frame_num=1024, kv_cache_sliding_window=64,
                      kv_cache_scale_frames=8, kv_cache_cross_frame_special=True,
                      kv_cache_include_scale_frames=True, use_sdpa=True,
                      camera_num_iterations=4)
    sd = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    model.load_state_dict(sd.get("model", sd), strict=False)
    model = model.to(device).eval()
    if dtype != torch.float32:
        model.aggregator = model.aggregator.to(dtype=dtype)

    images = load_and_preprocess_images(frames, mode="crop",
                                        image_size=image_size, patch_size=14)
    if jitter:
        g = torch.Generator().manual_seed(0)
        images = images * (1.0 + jitter * torch.randn(images.shape, generator=g))
    sync()
    t_load = time.time() - t_total0

    t_inf0 = time.time()
    preds = model.inference_streaming(images.to(device),
                                      num_scale_frames=scale_frames,
                                      keyframe_interval=1)
    sync()
    t_inf = time.time() - t_inf0

    # demo.py's postprocess: pose encoding -> extrinsics/intrinsics. It
    # then inverts w2c to c2w for the viewer; the unprojection helper wants
    # the world-from-camera one and inverts it itself, so the raw w2c
    # extrinsic is what goes in.
    h, w = images.shape[-2:]
    extri, intri = pose_encoding_to_extri_intri(preds["pose_enc"], (h, w))
    extri = extri[0].float().cpu().numpy()
    intri = intri[0].float().cpu().numpy()
    depth = preds["depth"][0].float().cpu().numpy()          # [S, H, W, 1]
    conf = preds["depth_conf"][0].float().cpu().numpy()      # [S, H, W]
    rgb = images.float().cpu().numpy()                       # [S, 3, H, W]

    world = unproject_depth_map_to_point_map(depth, extri, intri)  # [S,H,W,3]

    xyz, col, per_frame = [], [], []
    for s in range(world.shape[0]):
        m = conf[s][::pixel_stride, ::pixel_stride] > conf_thr
        p = world[s][::pixel_stride, ::pixel_stride][m]
        c = rgb[s].transpose(1, 2, 0)[::pixel_stride, ::pixel_stride][m]
        xyz.append(p)
        col.append(np.clip(np.rint(c * 255.0), 0, 255).astype(np.uint8))
        per_frame.append(len(p))
    # Cumulative, so it lines up with what the port prints per frame.
    print("ref_cumulative " + " ".join(str(n) for n in np.cumsum(per_frame)),
          file=sys.stderr)
    xyz = np.concatenate(xyz).astype(np.float32)
    col = np.concatenate(col)

    with open(out_path, "wb") as f:
        f.write(b"ply\nformat binary_little_endian 1.0\n"
                b"comment lingbot-map reference\n")
        f.write(("element vertex %d\n" % len(xyz)).encode())
        f.write(b"property float x\nproperty float y\nproperty float z\n"
                b"property uchar red\nproperty uchar green\nproperty uchar blue\n"
                b"end_header\n")
        for p, c in zip(xyz, col):
            f.write(struct.pack("<fffBBB", p[0], p[1], p[2], c[0], c[1], c[2]))

    t_total = time.time() - t_total0
    print("ref_seconds %.2f %.2f %.2f" % (t_total, t_load, t_inf), file=sys.stderr)
    print("%d points to %s" % (len(xyz), out_path))


if __name__ == "__main__":
    main()
