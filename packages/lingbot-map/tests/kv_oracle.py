#!/usr/bin/env python3
"""Reference for tests/kvcheck.nu — the KV-cache eviction bookkeeping.

This replays the reference's own eviction, from
lingbot_map/layers/attention.py::_apply_kv_cache_eviction_causal, on
frame indices instead of tensors. That function is 40 lines of slicing
whose only observable effect on the port is WHICH frames stay live and
how many rows that is, so a faithful replay of the slicing answers the
question a 300-frame model run would answer, in a second.

Validating this against the model itself needs 73+ frames through a
909M-parameter transformer on both sides. This is what is affordable,
and it is not a restatement of the port's own formulas — it is the
reference's control flow, run.
"""
import sys

P = 783            # tokens per frame at 518x294
SPECIAL = 6        # camera + 4 registers + scale
SCALE_FRAMES = 8   # kv_cache_scale_frames
WINDOW = 64        # kv_cache_sliding_window
FRAMES = 120


def main():
    # cache[i] is a frame index held in full; specials is a count of
    # frames kept as their six special rows only.
    cache, specials = [], 0
    rows = []
    for f in range(FRAMES):
        # ORDER MATTERS, and it is not the order the function's own body
        # suggests: attention.py:239-244 concatenates this frame into the
        # cache and THEN calls _apply_kv_cache_eviction_causal, so the
        # eviction counts the current frame. Evicting first would leave
        # the live set one frame too wide and start it one frame too
        # late.
        cache.append(f)
        num_cached = len(cache)
        if num_cached > WINDOW + SCALE_FRAMES:
            evict_start = SCALE_FRAMES
            evict_end = num_cached - WINDOW
            if evict_end > evict_start:
                evicted = cache[evict_start:evict_end]
                specials += len(evicted)            # cross_frame_special
                cache = cache[:SCALE_FRAMES] + cache[-WINDOW:]
        live = len(cache) * P + specials * SPECIAL
        rows.append((f, len(cache), specials, live))

    print("kv_frames %d | %s" % (FRAMES,
                                 " ".join(str(r[1]) for r in rows)))
    print("kv_specials %d | %s" % (FRAMES,
                                   " ".join(str(r[2]) for r in rows)))
    print("kv_live %d | %s" % (FRAMES, " ".join(str(r[3]) for r in rows)))
    # The high-water mark is what a cache has to be allocated for.
    print("kv_rows 1 | %d" % max(r[3] for r in rows))
    # the port additionally asserts its own placement is in range
    print("kv_bad 2 | 0 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
