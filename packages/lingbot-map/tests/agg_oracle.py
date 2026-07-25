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
    # Small tensors are dumped whole — a 9-element pose sampled every
    # 9973rd element is one number, which compares nothing.
    vals = flat.tolist() if flat.numel() <= 64 else flat[::STRIDE].tolist()
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

    taps = [int(x) for x in os.environ.get("LINGBOT_TAPS", "4,11,17,23").split(",")]
    if os.environ.get("LINGBOT_STREAM"):
        # Streaming: one frame per call, the KV cache carrying context
        # forward. This is what the model is FOR, and the second frame's
        # outputs are the first thing a cache bug shows up in.
        for fi in range(images.shape[0]):
            outs, psi = agg(imgs[:, fi:fi + 1], selected_idx=taps)
            for i, o in enumerate(outs):
                dump("stream%d_out_%d" % (fi, i), o)
        return
    outs, psi = agg(imgs, selected_idx=taps)
    print("patch_start_idx %d outputs %d" % (psi, len(outs)))
    for i, o in enumerate(outs):
        dump("agg_out_%d" % i, o)

    # the camera head reads the LAST tapped layer's camera token
    poses = model.camera_head([o.float() for o in outs], num_iterations=4)
    for i, p in enumerate(poses):
        dump("pose_iter_%d" % i, p)

    depth, depth_conf = model.depth_head([o.float() for o in outs],
                                         images=imgs.float(), patch_start_idx=psi)
    dump("depth", depth)
    dump("depth_conf", depth_conf)

    if os.environ.get("LINGBOT_DPT_TRACE"):
        # Re-walk the head's own submodules so each stage can be compared
        # against the port. Same code path, just observable.
        dh = model.depth_head
        ph, pw = images.shape[-2] // 14, images.shape[-1] // 14
        feats = []
        for i in range(4):
            x = outs[i].float()[:, :, psi:].reshape(-1, ph * pw, outs[i].shape[-1])
            x = dh.norm(x)
            x = x.permute(0, 2, 1).reshape(x.shape[0], x.shape[-1], ph, pw)
            x = dh.projects[i](x)
            dump("dpt_proj_%d" % i, x)
            x = dh._apply_pos_embed(x, images.shape[-1], images.shape[-2])
            dump("dpt_pos_%d" % i, x)
            x = dh.resize_layers[i](x)
            dump("dpt_rs_%d" % i, x)
            feats.append(x)
        rns = [dh.scratch.layer1_rn(feats[0]), dh.scratch.layer2_rn(feats[1]),
               dh.scratch.layer3_rn(feats[2]), dh.scratch.layer4_rn(feats[3])]
        for i, r in enumerate(rns):
            dump("dpt_rn_%d" % i, r)
        o = dh.scratch.refinenet4(rns[3], size=rns[2].shape[2:])
        dump("dpt_f4", o)
        o = dh.scratch.refinenet3(o, rns[2], size=rns[1].shape[2:])
        dump("dpt_f3", o)
        o = dh.scratch.refinenet2(o, rns[1], size=rns[0].shape[2:])
        dump("dpt_f2", o)
        o = dh.scratch.refinenet1(o, rns[0])
        dump("dpt_f1", o)
        o = dh.scratch.output_conv1(o)
        dump("dpt_oc1", o)


if __name__ == "__main__":
    main()
