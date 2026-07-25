#!/usr/bin/env python3
"""torch reference for tests/fusecheck.nu — the has_residual=False path
of a DPT FeatureFusionBlock (refinenet4), on the same synthetic weights.

This drives the reference's OWN FeatureFusionBlock, not a transcription
of it. An earlier version of this file re-implemented the block from a
reading of the source and reproduced a misreading: the reference builds
its residual units with nn.ReLU(inplace=True), so the first activation
overwrites the input and the residual added at the end is relu(x), not
x. A hand-written oracle agreed with the port's identical mistake and
the unit test passed while the real head was wrong by three orders of
magnitude. Importing the module cannot drift from it.
"""
import math
import os
import sys

import torch

sys.path.insert(0, os.path.expanduser("~/dev/lingbot-map"))
torch.set_grad_enabled(False)

from lingbot_map.heads.dpt_head import _make_fusion_block  # noqa: E402

CH, H, W, OH, OW = 8, 3, 5, 6, 10


def gen(n, phase):
    return torch.tensor([0.5 * math.sin(phase + 0.037 * j) for j in range(n)],
                        dtype=torch.float64)


def conv(cout, cin, k, phase):
    return (gen(cout * cin * k * k, phase).reshape(cout, cin, k, k),
            gen(cout, phase + 0.5))


def row(label, t):
    def fmt(v):
        return str(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v)
    flat = t.reshape(-1).tolist()
    print("%s 1x%d | %s" % (label, len(flat), " ".join(fmt(v) for v in flat)))


def main():
    blk = _make_fusion_block(CH, has_residual=False).double().eval()
    for mod, phase in ((blk.resConfUnit2.conv1, 1.7),
                       (blk.resConfUnit2.conv2, 2.1),
                       (blk.out_conv, 2.5)):
        w, b = conv(mod.out_channels, mod.in_channels,
                    mod.kernel_size[0], phase)
        mod.weight.copy_(w)
        mod.bias.copy_(b)

    x = gen(CH * H * W, 0.11).reshape(1, CH, H, W)
    row("fc_in", x)
    # The port dumps the same three probes, so a divergence lands on one
    # step. Everything here runs on a clone, because the block's in-place
    # activation would otherwise edit what was already printed.
    o = blk.resConfUnit2(x.clone())
    row("fc_rcu", o)
    up = torch.nn.functional.interpolate(o, size=(OH, OW), mode="bilinear",
                                         align_corners=blk.align_corners)
    row("fc_up", up)
    row("fc_out", blk.out_conv(up))
    # And once through the block as a whole, which is what the port's
    # _dp_fuse_fwd is; fusecheck prints fc_out three times over.
    out = blk(x.clone(), size=(OH, OW))
    row("fc_blk", out)
    row("fc_vec", out)


if __name__ == "__main__":
    main()
