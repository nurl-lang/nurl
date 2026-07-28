#!/usr/bin/env python3
"""The reference, end to end, on an explicit list of frames.

Runs load_images + model.infer in fp32 (TF32 off, no amp, no masking)
and dumps every view's pts3d in row-major pixel order, concatenated —
exactly the vertex order the port's PLY has when run with --no-mask.
Also dumps poses, conf and the metric scale for diagnostics.

Usage: e2e_oracle.py <outdir> <frame> [frame ...]
"""

import sys

import numpy as np
import torch

from mapanything.models import MapAnything
from mapanything.utils.image import load_images

torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False

MODEL = "/home/wau/.nurl/models/models/facebook_map-anything-apache/snapshots/main"


def main():
    outdir = sys.argv[1]
    frames = sys.argv[2:]
    views = load_images(frames)
    print("views %d shape %s" % (len(views), tuple(views[0]["img"].shape)))

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    m = MapAnything.from_pretrained(MODEL).to(dev).eval()
    for v in views:
        v["img"] = v["img"].to(dev)
    with torch.no_grad():
        preds = m.infer(
            views,
            memory_efficient_inference=False,
            use_amp=False,
            apply_mask=False,
            mask_edges=False,
        )

    pts = np.concatenate(
        [p["pts3d"][0].cpu().numpy().reshape(-1, 3) for p in preds], axis=0
    )
    pts.astype(np.float32).tofile(f"{outdir}/ref_e2e_pts.bin")
    np.stack(
        [
            np.concatenate(
                [p["cam_trans"][0].cpu().numpy(), p["cam_quats"][0].cpu().numpy()]
            )
            for p in preds
        ]
    ).astype(np.float32).tofile(f"{outdir}/ref_e2e_poses.bin")
    scale = float(preds[0]["metric_scaling_factor"])
    with open(f"{outdir}/ref_e2e_scale.txt", "w") as f:
        f.write(str(scale))
    print("scale", scale, "pts", pts.shape)


if __name__ == "__main__":
    main()
