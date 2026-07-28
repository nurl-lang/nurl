#!/usr/bin/env python3
"""The reference geometry + masks over deterministic inputs.

Drives convert_ray_dirs_depth_along_ray_pose_trans_quats_to_pointmap,
points_to_normals, normals_edge and depth_edge — the reference's own
functions — over a synthetic scene with real depth discontinuities, and
combines them exactly as inference.py does.

Writes: dirs.bin [3,H,W] (unnormalised; both sides normalise),
depth.bin [H,W], pose.bin [7] (t + quat xyzw, unnormalised),
logits.bin [H,W], ref_pts.bin [H,W,3], ref_mask.bin [H,W] u8.

Usage: geom_oracle.py <outdir> [H W]  (default 84 148)
"""

import sys

import numpy as np
import torch

sys.path.insert(0, "/home/wau/dev/map-anything")
from mapanything.utils.geometry import (
    convert_ray_dirs_depth_along_ray_pose_trans_quats_to_pointmap,
    depth_edge,
    normals_edge,
    points_to_normals,
)

SCALE = 1.7


def main():
    outdir = sys.argv[1]
    H = int(sys.argv[2]) if len(sys.argv) > 2 else 84
    W = int(sys.argv[3]) if len(sys.argv) > 3 else 148

    rng_y, rng_x = np.mgrid[0:H, 0:W]
    # pinhole-ish rays with structure
    dx = (rng_x - W / 2) / (W / 2)
    dy = (rng_y - H / 2) / (H / 2)
    dirs = np.stack([dx * 0.8, dy * 0.6, np.ones_like(dx)], 0).astype(np.float32)
    # depth: smooth field with a hard step and a blob (real discontinuities)
    depth = 2.0 + 0.3 * np.sin(rng_x / 9.0) + 0.2 * np.cos(rng_y / 7.0)
    depth[rng_y > H // 2] += 3.0
    blob = ((rng_x - W // 3) ** 2 + (rng_y - H // 3) ** 2) < (H // 6) ** 2
    depth[blob] = 0.8
    depth = depth.astype(np.float32)
    # logits: mostly positive, a corner masked out
    logits = np.ones((H, W), np.float32)
    logits[: H // 6, : W // 6] = -1.0
    pose = np.array([0.3, -0.2, 0.1, 0.1, -0.2, 0.3, 0.9], np.float32)

    dirs.tofile(f"{outdir}/dirs.bin")
    depth.tofile(f"{outdir}/depth.bin")
    pose.tofile(f"{outdir}/pose.bin")
    logits.tofile(f"{outdir}/logits.bin")

    dirs_n = dirs / np.linalg.norm(dirs, axis=0, keepdims=True).clip(1e-8)
    rd = torch.from_numpy(dirs_n.transpose(1, 2, 0))  # H,W,3
    dz = torch.from_numpy(depth)[..., None]
    pts = convert_ray_dirs_depth_along_ray_pose_trans_quats_to_pointmap(
        rd, dz, torch.from_numpy(pose[:3]), torch.from_numpy(pose[3:])
    )
    pts = (pts * SCALE).numpy()
    depth_z = (dz.numpy()[..., 0] * dirs_n[2]) * SCALE

    mask = logits > 0
    normals, normals_mask = points_to_normals(pts, mask=mask)
    nedge = normals_edge(normals, tol=5.0, mask=normals_mask)
    dedge = depth_edge(depth_z, rtol=0.03, mask=mask)
    final = mask & ~(dedge & nedge)

    pts.astype(np.float32).tofile(f"{outdir}/ref_pts.bin")
    final.astype(np.uint8).tofile(f"{outdir}/ref_mask.bin")
    print("kept %d / %d" % (final.sum(), final.size))


if __name__ == "__main__":
    main()
