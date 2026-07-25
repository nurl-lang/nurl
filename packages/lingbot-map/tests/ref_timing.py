#!/usr/bin/env python3
"""How long does the REFERENCE take for one frame on this machine?

The port runs on gpukit's CPU backend because there is no usable GPU
here; torch runs on CPU for the same reason. So this is like for like,
and it is the only honest answer to "is the port fast".

Model construction and checkpoint load are excluded — they are paid once
and the port excludes them too. Reported: aggregator, camera head and
depth head for a single frame, best of N.

  ref_timing.py <checkpoint.pt> <frame.png> [runs]
"""
import os
import sys
import time

import torch

sys.path.insert(0, os.path.expanduser("~/dev/lingbot-map"))
torch.set_grad_enabled(False)

from lingbot_map.models.gct_stream import GCTStream          # noqa: E402
from lingbot_map.utils.load_fn import load_and_preprocess_images  # noqa: E402


def main():
    ckpt_path, frame = sys.argv[1], sys.argv[2]
    runs = int(sys.argv[3]) if len(sys.argv) > 3 else 3

    model = GCTStream(img_size=518, patch_size=14, enable_3d_rope=True,
                      max_frame_num=1024, kv_cache_sliding_window=64,
                      kv_cache_scale_frames=8, kv_cache_cross_frame_special=True,
                      kv_cache_include_scale_frames=True, use_sdpa=True,
                      camera_num_iterations=4)
    sd = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    model.load_state_dict(sd.get("model", sd), strict=False)
    model.eval()

    images = load_and_preprocess_images([frame], image_size=518, patch_size=14)
    imgs = images[None]
    taps = [4, 11, 17, 23]

    print("threads %d  frame %s" % (torch.get_num_threads(),
                                    "x".join(str(d) for d in images.shape)))
    best = None
    for i in range(runs):
        # a fresh cache each run, so run 2 is not a cached-KV freebie
        model.aggregator.kv_cache = None if hasattr(
            model.aggregator, "kv_cache") else None
        t0 = time.perf_counter()
        outs, _psi = model.aggregator(imgs, selected_idx=taps)
        t1 = time.perf_counter()
        model.camera_head([o.float() for o in outs], num_iterations=4)
        t2 = time.perf_counter()
        model.depth_head([o.float() for o in outs], images=imgs.float(),
                         patch_start_idx=_psi)
        t3 = time.perf_counter()
        tot = t3 - t0
        print("run %d  aggregator %.1f s  camera %.1f s  depth %.1f s  "
              "total %.1f s" % (i, t1 - t0, t2 - t1, t3 - t2, tot))
        best = tot if best is None else min(best, tot)
    print("BEST %.1f s" % best)


if __name__ == "__main__":
    main()
