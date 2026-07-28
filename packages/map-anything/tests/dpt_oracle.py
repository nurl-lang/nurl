#!/usr/bin/env python3
"""The reference DPT dense head + adaptors over deterministic inputs.

Drives m.dense_head (DPTFeature + DPTRegressionProcessor) and
m.dense_adaptor directly, one view, batch 1.

Writes into <outdir>:
  hooks.bin      f32 [4, np, 1536]  synthetic tapped features (token-major)
  ref_rays.bin   f32 [3, H, W]
  ref_depth.bin  f32 [H, W]
  ref_conf.bin   f32 [H, W]
  ref_mask.bin   f32 [H, W]   (raw logits)

Usage: dpt_oracle.py <outdir> [gh gw]   (default 21 37 → 294×518)
"""

import sys

import numpy as np
import torch

from mapanything.models import MapAnything
from uniception.models.prediction_heads.adaptors import AdaptorInput
from uniception.models.prediction_heads.base import PredictionHeadLayeredInput

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
    np_tok = gh * gw

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    m = MapAnything.from_pretrained(MODEL).to(dev).eval()

    hooks = [field((1, 1536, gh, gw), s) for s in range(4)]
    np.stack([h.transpose(0, 2, 3, 1).reshape(np_tok, 1536) for h in hooks]).tofile(
        f"{outdir}/hooks.bin"
    )

    with torch.no_grad():
        inp = PredictionHeadLayeredInput(
            list_features=[torch.from_numpy(h).to(dev) for h in hooks],
            target_output_shape=(H, W),
        )
        decoded = m.dense_head(inp)  # PixelTaskOutput, decoded_channels [1,6,H,W]
        adapted = m.dense_adaptor(
            AdaptorInput(adaptor_feature=decoded.decoded_channels, output_shape_hw=(H, W))
        )

    val = adapted.value.cpu().numpy()  # [1, 4, H, W]: raydirs 3 + depth 1
    val[0, :3].astype(np.float32).tofile(f"{outdir}/ref_rays.bin")
    val[0, 3].astype(np.float32).tofile(f"{outdir}/ref_depth.bin")
    adapted.confidence.cpu().numpy()[0, 0].astype(np.float32).tofile(f"{outdir}/ref_conf.bin")
    adapted.logits.cpu().numpy()[0, 0].astype(np.float32).tofile(f"{outdir}/ref_mask.bin")
    print("wrote gh=%d gw=%d H=%d W=%d" % (gh, gw, H, W))


if __name__ == "__main__":
    main()
