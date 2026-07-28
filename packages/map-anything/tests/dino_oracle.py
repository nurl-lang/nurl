#!/usr/bin/env python3
"""The reference encoder over a deterministic input, dumped as binary.

Drives m.encoder itself (uniception DINOv2Encoder wrapping the 24-block
truncated dinov2_vitg14) so torch-hub construction, pos-embed
interpolation and the Identity final norm are all the reference's own.

Writes into <outdir>:
  input.bin    f32 [3, H, W] planar — a pseudo-random field, ALREADY
               "normalised" (values in roughly [-2, 2]; the encoder does
               not normalise, it only checks the declared type)
  ref_tok.bin  f32 [1 + gh*gw, 1536] — cls row, then patch tokens

Usage: dino_oracle.py <outdir> [H W]   (default 392 518 → 28×37 grid,
which exercises the pos-embed resample; 518 518 exercises the skip)
"""

import sys

import numpy as np
import torch

from mapanything.models import MapAnything
from uniception.models.encoders.base import ViTEncoderInput

# The reference flips TF32 on at import time (model.py, uniception
# transformer_blocks.py). For an oracle that a true-f32 port is compared
# against, that is ~1e-3 of noise — turn it back off.
torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False

MODEL = "/home/wau/.nurl/models/models/facebook_map-anything-apache/snapshots/main"


def main():
    outdir = sys.argv[1]
    H = int(sys.argv[2]) if len(sys.argv) > 2 else 392
    W = int(sys.argv[3]) if len(sys.argv) > 3 else 518

    c = np.arange(3)[:, None, None]
    y = np.arange(H)[None, :, None]
    x = np.arange(W)[None, None, :]
    v = (37 * x + 61 * y + 91 * c + 13 * ((x * y) % 7)) % 251
    img = (v / 251.0 * 4.0 - 2.0).astype(np.float32)
    img.tofile(f"{outdir}/input.bin")

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    m = MapAnything.from_pretrained(MODEL).to(dev).eval()
    with torch.no_grad():
        out = m.encoder(
            ViTEncoderInput(image=torch.from_numpy(img)[None].to(dev), data_norm_type="dinov2")
        )
    feat = out.features  # [1, 1536, gh, gw]
    _, dim, gh, gw = feat.shape
    patches = feat.permute(0, 2, 3, 1).reshape(-1, dim)
    cls = out.registers.reshape(1, dim)  # [B, dim, 1] — just the cls token here
    tok = torch.cat([cls, patches], dim=0).cpu().numpy().astype(np.float32)
    tok.tofile(f"{outdir}/ref_tok.bin")
    print("wrote", tok.shape, "grid", gh, gw)


if __name__ == "__main__":
    main()
