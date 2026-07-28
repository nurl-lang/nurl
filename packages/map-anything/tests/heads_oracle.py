#!/usr/bin/env python3
"""The reference pose + scale heads over deterministic inputs.

Drives m.pose_head + m.pose_adaptor and m.scale_head + m.scale_adaptor
directly. Writes:
  pfeat.bin   f32 [np, 1536]  synthetic final features (token-major)
  stok.bin    f32 [1536]      synthetic final scale token
  ref_pose.bin f32 [7]        [t(3) | quat(4) normalised]
  ref_scale.bin f32 [1]

Usage: heads_oracle.py <outdir> [gh gw]  (default 21 37)
"""

import sys

import numpy as np
import torch

from mapanything.models import MapAnything
from uniception.models.prediction_heads.adaptors import AdaptorInput
from uniception.models.prediction_heads.base import (
    PredictionHeadInput,
    PredictionHeadTokenInput,
)

torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False

MODEL = "/home/wau/.nurl/models/models/facebook_map-anything-apache/snapshots/main"


def field(shape, seed):
    n = int(np.prod(shape))
    idx = np.arange(n)
    v = (37 * idx + 13 * ((idx * (seed + 3)) % 7) + 91 * seed) % 251
    return ((v / 251.0) * 2.0 - 1.0).astype(np.float32).reshape(shape)


def main():
    outdir = sys.argv[1]
    gh = int(sys.argv[2]) if len(sys.argv) > 2 else 21
    gw = int(sys.argv[3]) if len(sys.argv) > 3 else 37
    H, W = gh * 14, gw * 14

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    m = MapAnything.from_pretrained(MODEL).to(dev).eval()

    feat = field((1, 1536, gh, gw), 7)
    stok = field((1, 1536, 1), 42)
    feat.transpose(0, 2, 3, 1).reshape(-1, 1536).tofile(f"{outdir}/pfeat.bin")
    stok.reshape(1536).tofile(f"{outdir}/stok.bin")

    with torch.no_grad():
        ph = m.pose_head(PredictionHeadInput(last_feature=torch.from_numpy(feat).to(dev)))
        pose = m.pose_adaptor(
            AdaptorInput(adaptor_feature=ph.decoded_channels, output_shape_hw=(H, W))
        )
        sh = m.scale_head(
            PredictionHeadTokenInput(last_feature=torch.from_numpy(stok).to(dev))
        )
        scale = m.scale_adaptor(
            AdaptorInput(adaptor_feature=sh.decoded_channels, output_shape_hw=(H, W))
        )

    pose.value.cpu().numpy().reshape(7).astype(np.float32).tofile(f"{outdir}/ref_pose.bin")
    scale.value.cpu().numpy().reshape(1).astype(np.float32).tofile(f"{outdir}/ref_scale.bin")
    print("pose", pose.value.cpu().numpy().reshape(7), "scale", float(scale.value))


if __name__ == "__main__":
    main()
