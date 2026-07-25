#!/usr/bin/env python3
"""How long does the REFERENCE take for one frame on this machine?

Model construction and checkpoint load are excluded — they are paid once
and the port excludes them too. Reported: aggregator, camera head and
depth head for a single frame, best of N.

  ref_timing.py <checkpoint.pt> <frame.png> [runs] [device] [dtype]

device is cuda or cpu (default: cuda when available). dtype is what the
AGGREGATOR runs in; the heads always run fp32, which is what demo.py
does. `float32` is the like-for-like comparison against the port, which
is fp32 throughout; `bf16` is how demo.py actually runs on a card with
compute capability 8 or better, and is the number to beat if the claim
is "as fast as the reference as shipped".
"""
import os
import sys
import time

import torch

sys.path.insert(0, os.path.expanduser("~/dev/lingbot-map"))
torch.set_grad_enabled(False)

from lingbot_map.models.gct_stream import GCTStream          # noqa: E402
from lingbot_map.utils.load_fn import load_and_preprocess_images  # noqa: E402

DTYPES = {"float32": torch.float32, "fp32": torch.float32,
          "bfloat16": torch.bfloat16, "bf16": torch.bfloat16,
          "float16": torch.float16, "fp16": torch.float16}


def main():
    ckpt_path, frame = sys.argv[1], sys.argv[2]
    runs = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    dev = sys.argv[4] if len(sys.argv) > 4 else (
        "cuda" if torch.cuda.is_available() else "cpu")
    dtype = DTYPES[sys.argv[5]] if len(sys.argv) > 5 else torch.float32
    device = torch.device(dev)
    cuda = device.type == "cuda"

    model = GCTStream(img_size=518, patch_size=14, enable_3d_rope=True,
                      max_frame_num=1024, kv_cache_sliding_window=64,
                      kv_cache_scale_frames=8, kv_cache_cross_frame_special=True,
                      kv_cache_include_scale_frames=True, use_sdpa=True,
                      camera_num_iterations=4)
    sd = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    model.load_state_dict(sd.get("model", sd), strict=False)
    model = model.to(device).eval()
    # demo.py casts the aggregator to the inference dtype and keeps the
    # heads in fp32; mirror that exactly rather than autocasting the lot.
    if dtype != torch.float32:
        model.aggregator = model.aggregator.to(dtype=dtype)

    images = load_and_preprocess_images([frame], image_size=518, patch_size=14)
    imgs = images[None].to(device)
    taps = [4, 11, 17, 23]

    def sync():
        if cuda:
            torch.cuda.synchronize()

    print("device %s  dtype %s  frame %s" % (
        dev, str(dtype).replace("torch.", ""),
        "x".join(str(d) for d in images.shape)))
    best = None
    for i in range(runs):
        # a fresh cache each run, so run 2 is not a cached-KV freebie
        model.aggregator.kv_cache = None
        sync()
        t0 = time.perf_counter()
        with torch.amp.autocast(device.type, dtype=dtype,
                                enabled=(dtype != torch.float32)):
            outs, _psi = model.aggregator(imgs.to(dtype), selected_idx=taps)
        sync()
        t1 = time.perf_counter()
        model.camera_head([o.float() for o in outs], num_iterations=4)
        sync()
        t2 = time.perf_counter()
        model.depth_head([o.float() for o in outs], images=imgs.float(),
                         patch_start_idx=_psi)
        sync()
        t3 = time.perf_counter()
        tot = t3 - t0
        print("run %d  aggregator %.3f s  camera %.3f s  depth %.3f s  "
              "total %.3f s" % (i, t1 - t0, t2 - t1, t3 - t2, tot))
        best = tot if best is None else min(best, tot)
    print("BEST %.3f s" % best)


if __name__ == "__main__":
    main()
