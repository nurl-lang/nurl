#!/usr/bin/env python3
"""The reference info_sharing over deterministic inputs, dumped as binary.

Drives m.fusion_norm_layer + m.info_sharing exactly as model.py composes
them for the images-only path: fusion norm on the per-view features (not
the registers), registers appended per view, scale token appended
globally. Dumps the tap-7, tap-11 and final sequences in the port's own
layout ([v0 patches, v0 cls, v1 patches, v1 cls, ..., scale]).

Writes into <outdir>:
  feats.bin  f32 [V, np, 1536]  synthetic pre-fusion patch features
  regs.bin   f32 [V, 1536]      synthetic cls registers
  ref_tap7.bin / ref_tap11.bin  f32 [V*(np+1), 1536]
  ref_fin.bin                   f32 [V*(np+1)+1, 1536]

Usage: infoshare_oracle.py <outdir> [V gh gw]  (default 2 21 37)
"""

import sys

import numpy as np
import torch

from mapanything.models import MapAnything
from uniception.models.info_sharing.base import MultiViewTransformerInput

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
    V = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    gh = int(sys.argv[3]) if len(sys.argv) > 3 else 21
    gw = int(sys.argv[4]) if len(sys.argv) > 4 else 37
    np_tok = gh * gw

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    m = MapAnything.from_pretrained(MODEL).to(dev).eval()

    feats = [field((1, 1536, gh, gw), v) for v in range(V)]
    regs = [field((1, 1536, 1), 100 + v) for v in range(V)]
    np.stack([f.transpose(0, 2, 3, 1).reshape(np_tok, 1536) for f in feats]).tofile(
        f"{outdir}/feats.bin"
    )
    np.stack([r.reshape(1536) for r in regs]).tofile(f"{outdir}/regs.bin")

    with torch.no_grad():
        fused = []
        for f in feats:
            t = torch.from_numpy(f).to(dev).permute(0, 2, 3, 1)
            t = m.fusion_norm_layer(t).permute(0, 3, 1, 2).contiguous()
            fused.append(t)
        scale = m.scale_token.unsqueeze(0).unsqueeze(-1)  # (1, C, 1)
        inp = MultiViewTransformerInput(
            features=fused,
            additional_input_tokens_per_view=[torch.from_numpy(r).to(dev) for r in regs],
            additional_input_tokens=scale,
        )
        final, inters = m.info_sharing(inp)

    def seq(out, with_scale):
        rows = []
        for v in range(V):
            f = out.features[v]  # (1, C, gh, gw)
            rows.append(f.permute(0, 2, 3, 1).reshape(np_tok, 1536))
            r = out.additional_token_features_per_view[v]  # (1, C, 1)
            rows.append(r.permute(0, 2, 1).reshape(1, 1536))
        if with_scale:
            rows.append(out.additional_token_features.permute(0, 2, 1).reshape(1, 1536))
        return torch.cat(rows, 0).cpu().numpy().astype(np.float32)

    seq(inters[0], False).tofile(f"{outdir}/ref_tap7.bin")
    seq(inters[1], False).tofile(f"{outdir}/ref_tap11.bin")
    seq(final, True).tofile(f"{outdir}/ref_fin.bin")
    print("wrote V=%d np=%d n=%d" % (V, np_tok, V * (np_tok + 1) + 1))


if __name__ == "__main__":
    main()
