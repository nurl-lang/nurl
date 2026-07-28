# lingbot-map — porting notes

How the port was built and what it cost, kept out of the
[README](../README.md) because none of it is needed to use the thing.
It is here because the next person to touch the model code will want it:
the traps below are all silent ones — nothing crashes, no shape is wrong,
the reconstruction is just quietly not the reference's.

## Why this port is the size it is

The reference is ~13 000 lines of PyTorch and the checkpoint is 4.6 GB
of fp32 — roughly 1.16 B parameters in three stacked transformers:

| part | shape |
|---|---|
| `patch_embed` | DINOv2 ViT-L/14 — 24 blocks, dim 1024, used as a frozen feature extractor |
| `aggregator.frame_blocks` | 24 blocks, dim 1024 — attention **within** a frame |
| `aggregator.global_blocks` | 24 blocks, dim 1024 — causal attention **across** frames, over a paged KV cache |
| `camera_head` | iterative pose refinement, 4 passes |
| `depth_head`, `point_head` | DPT decoders over four intermediate layers |

Frame and global blocks alternate, and every fourth pair (`[4, 11, 17,
23]`) is tapped for the DPT heads. That structure — anchor context,
pose-reference window, trajectory memory — is the paper's contribution
and is what the port has to reproduce exactly, not approximately.

## Stages

| # | stage | state |
|---|---|---|
| 1 | read the `.pt` checkpoint | **done** — [`torchpt`](../../torchpt); the real 4.6 GB file in 0.01 s / 31 MB RSS, values identical to `torch.load` |
| 2 | image loading and preprocessing | **done** — byte-identical to the reference pipeline on real frames |
| 3 | ViT layers: patch embed, 2-D RoPE, qk-norm attention, block | **done** — the full block matches the reference to 4e-15 |
| 4 | streaming aggregator + KV cache | **done** — 5.9e-6 vs the real model; sliding-window eviction 8.5e-6, checked against the model past the eviction point |
| 5 | camera head, DPT heads | **done** — camera head 2.2e-7, DPT depth head 1.6e-6 |
| 6 | camera geometry | **done** — matches torch to 2.4e-16 |
| 7 | CLI, point-cloud export, end-to-end check | **done** — `src/main.nu`; world points 1.5e-6 vs the real model |

## The speed work — what made the difference

The port was correct long before it was fast: eight frames took 38.2 s
end to end and the 4.6 GB checkpoint load alone was ~25 s. Those are now
2.8 s and 1.6 s, on an RTX 4090, with the per-frame steady state down
from ~1.25 s to ~0.16 s. Every kernel rewrite kept its accumulation
order, so this is the same arithmetic run in a better shape — with one
deliberate exception, the fused attention, noted below.

Nearly all of it is in [`gpukit`](../../gpukit) rather than here — this port
was the thing that made the gaps visible, and the fixes belong where
every GPU package gets them. In rough order of what it bought:

* **Tiled GEMM.** One thread per output element costs a global load of B
  per multiply-add; a 64x64 shared-memory tile with a 4x4 register tile
  and `float4` shared reads costs a fraction of one. 3.1 → 19.1 TFLOP/s
  (and 0.6 → 20.1 with a transposed B, which the old kernel read along
  the wrong axis entirely). Bit-identical: blocking changes when a
  product is computed, not the order the sum runs in.
* **Fused attention.** The composed form materialises a
  `[heads, n, nkv]` score matrix, writes it once and reads it five
  times. `gkd_attention` never writes it. 3.8x at `nkv = n`, 6.2x at
  `nkv = 4n` — and, more to the point for a *streaming* model, the
  buffer it does not allocate is 2.8 GB at a 72-frame window. This is
  the one change that is not bit-identical (an online softmax rescales a
  running sum rather than summing left to right); it moved the whole
  aggregator from 5.385e-6 to 5.853e-6 against the real model, and the
  end-to-end depth agreement *improved*, from 1.646e-5 to 1.591e-5 —
  which figures, since the reference uses SDPA and so does this.
* **A caching device allocator.** `cuMemAlloc`/`cuMemFree` synchronise
  and cost ~315 us per 12 MB pair. A frame allocates its scratch a few
  hundred times, so a third of every frame was the allocator, with the
  device idle for all of it.
* **The checkpoint is read straight into device memory.** The load path
  widened every f32 weight to f64, transposed the four hot Linear
  weights on the host with a column-strided write per element, and
  narrowed them again on upload. Now the mapped bytes go to the device
  as they are and the transpose is a permute kernel: 25 s → 1.6 s.
* **Layernorm a row per block, not per thread** (~800 rows is three
  blocks on a 128-SM card): 6.3x. **Convolution with a 4x4 output tile
  per thread**: 2.2x. **Transposed convolution** with a fast path for
  stride == kernel, where the general body was doing two 64-bit modulos
  per tap to discover that fifteen of every sixteen taps contribute
  nothing: 14.2 ms → 0.35 ms. **GEMV shape for M = 1**, which the camera
  head runs twenty times per frame and which was eight blocks on a
  128-SM card.
* **The convolution is shape-specialised too**, for the same reason as
  the permute: every loop bound and stride was a kernel argument, so a
  3x3 layer paid a 64-bit multiply-add chain per tap to compute an
  address the compiler could have folded, and could not unroll a
  nine-tap window it did not know was nine taps. The twelve dimensions
  go in as literals; each layer geometry compiles once. The depth head
  went 39 ms → 22 ms, and the dumps are byte-identical with the
  specialisation forced off.
* **The permute is shape-specialised.** The generic body decomposed
  each output index with six 64-bit divisions and modulos and kept its
  working arrays in local memory, which is why moving 9 MB took 87 us.
  The kernel source is generated per call anyway, so the dims and the
  permutation go in as literals and it takes 15 us.
* **Two per-frame constants are now built once.** The DPT
  positional-embedding grid is a pure function of (channels, height,
  width, aspect); rebuilding it was ~10 million host `sin`/`cos` a
  frame, a fifth of the frame. The DINOv2 position grid is a bicubic
  resample over 1024 channels and a pure function of (gh, gw);
  rebuilding it was another 53 ms a frame — a *quarter* of what the
  frame had shrunk to by then. Both were found the same way, by
  profiling a build without LTO so the inlined frame loop resolves into
  named functions, and both are bit-identical: the eight-frame cloud is
  byte-for-byte unchanged.
* **The point cloud is binary PLY by default.** ASCII cost 15 us per
  point — 470 ms a frame at the default stride, more than the depth
  head. `--ascii` still writes the text form, and the two select exactly
  the same points.
  The float formatting behind it was worth fixing on its own:
  `nurl_str_float` searched 1..17 significant digits linearly for the
  shortest round-trip, which is ~2.5 us for a value that came from an
  f32 (the worst case). It binary-searches now — the property is
  monotone in the digit count — which is five probes instead of
  seventeen, for every float any NURL program prints.

Four things this did NOT need, all measured and dropped: double
buffering the GEMM's global loads (neutral — the kernel is not
latency-bound), a 128x128 tile with an 8x8 register tile (worse — at
these shapes it halves the block count on a 128-SM card, and idle SMs
cost more than the better reuse gains; worse again when re-tried after
the `float4` change, this time on register pressure), and 16-byte global
loads in the staging phase (also neutral-to-worse, so it is not
issue-bound on those either). Four negative results on one kernel is
itself the finding: at ~25 TFLOP/s it is not short of any single
resource, and the next step is warp-level tiling with register-resident
fragments rather than another parameter.

The convolution and the attention, by contrast, were both short of
something specific and both moved a lot when it was fixed — which is the
argument for measuring each kernel rather than assuming the biggest one
is the one to work on.

## The stages, one at a time

Newest first, roughly — each section is what that stage cost to get
right, not what it does. The order below is the order they were
finished, which is not the order the model runs them in.

### Stage 2 — preprocessing (`src/preproc.nu`)

`load_and_preprocess_images(mode="crop", image_size=518, patch_size=14)`,
which is what `demo.py` runs: alpha onto white, RGB, bicubic resize to
width 518 with the height snapped to a whole number of patches, centre
crop, scale to [0, 1], CHW. ImageNet normalisation is *not* done here —
the aggregator does it, and doing it twice is a quiet way to get a
plausible but wrong reconstruction.

That needed a **PIL-compatible bicubic resampler**, which the `image`
package did not have (only nearest, bilinear and box). It has one now:
`image_resize_bicubic`, byte-identical to Pillow — same `a = −0.5`
kernel, same support scaling, same 22-bit fixed-point two-pass
arithmetic. Note that this is a *different kernel* from the one stage 3
needs for the position grid (torch's `a = −0.75`); they are not
interchangeable.

Verified on the repo's own example frames: six frames, every sampled
value identical to the reference pipeline.

EXIF orientation is deliberately **not** applied — the reference calls
`exif_transpose`, `image` does not surface EXIF, and silently ignoring a
rotation beats silently applying the wrong one. Video-derived frames,
which is what streaming reconstruction is actually fed, carry none.

### Stage 6 — camera geometry (`src/geom.nu`)

The model's per-frame output is a 9-vector: translation, a **scalar-last**
quaternion, and two field-of-view angles. `src/geom.nu` turns that into
extrinsics, intrinsics, a camera-to-world transform, and unprojected
world points.

Verified against the upstream `quat_to_mat` / `mat_to_quat` /
`pose_encoding_to_extri_intri` / `closed_form_inverse_se3` code paths:
worst relative error **2.4e-16** across six random pose encodings — the
last bit, and it comes from torch's vectorised `tan` disagreeing with
glibc's, not from the port.

### Stage 7 — the CLI, hardening pass

Three defects the finishing pass turned up, all in `src/main.nu`:

* **It always exited 0.** A frame could fail, the message went to
  stdout, and the process reported success — a caller piping the cloud
  into a build would never learn. Failures now set `rc` and it is
  returned.
* **The workspace was sized `nframes · P`.** Eviction caps the cache far
  below that, and the attention matrix is `heads · n · nkv`: at 300
  frames the oversized version wants ~12 GB for that term alone and
  would not run at all. It is now sized by `ag_kv_rows`, a 4× cut at
  300 frames.
* **No way to name a directory.** A 324-frame scene meant 324 paths on
  the command line. `--frames <dir>` takes every `.png`/`.jpg`, **sorted
  by name** — order is not a nicety, the KV cache makes frame N depend
  on every frame before it, so a raw `readdir` order reconstructs a
  different scene.

`vec_extend` looked like the way to append the glob results, and it
exposed a compiler bug: `= . p + k 0 v` for an aggregate element type
died with *"unknown field or variable: +"*. Fixed in `nurlc` with a
regression test (`compiler/tests/ptr_agg_index_store.nu`). `vec_extend`
documents itself as safe only for trivial element types, so the CLI
pushes the handles across instead.

### Stage 4 (partial) — KV-cache eviction (`src/aggregator.nu`)

The reference keeps the first `kv_cache_scale_frames` = 8 frames
forever, keeps the last `kv_cache_sliding_window` = 64 frames
**including the current one**, and from every frame it drops it
preserves the six special-token rows. Past 72 frames a cache that just
grows is not merely wasteful, it is **wrong** — the model attends to
frames it should not. The example scenes are 237–324 frames.

That "including the current one" is the whole subtlety, and it is not
visible in the eviction function. `attention.py:239-244` concatenates
the frame into the cache and only *then* calls
`_apply_kv_cache_eviction_causal`, so `num_cached` already counts it:
the trigger is `f ≥ S + W` and the live set is the scale frames plus
`f−W+1 … f`. The port first read the function alone, got a window one
frame too wide starting one frame too late, and was wrong from the very
first eviction — by **2.7e-2**.

The port implements the policy as a ring rather than as the reference's
repeated `torch.cat`. Each cache is laid out as

```
[0, S·P)              the scale frames, never moved
[S·P, S·P + W·P)      a ring of the last W frames
[S·P + W·P, …)        six preserved rows per evicted frame
```

The live region is always a **prefix**, so attention still reads a
contiguous run and nothing in the attention path had to learn about
eviction. Shifting the survivors down instead, which is what
`torch.cat` amounts to, would move about 5 GB per frame across 24
blocks.

That did force one honest change: `LmKv`'s single `used` became `woff`
and `nvalid`. Where a frame writes and how much of the cache is live are
the same number only while frames go on the end.

Two tests, and it took both:

* `tests/kvcheck.nu` vs `tests/kv_oracle.py` — the bookkeeping, 120
  frames, exact, one second. `kv_oracle.py` replays the reference's own
  eviction; it needs no torch and no checkpoint.
* `tests/streamcheck.nu` vs the real model with the window shrunk to
  **1 + 2 on both sides** (`LINGBOT_KV_SCALE` / `LINGBOT_KV_WINDOW`,
  which the reference takes as constructor arguments) — six frames,
  three of them past eviction, **7.7e-6**.

The bookkeeping test alone was not enough, and the reason is worth
keeping: `kv_oracle.py` replayed the reference's eviction *function*
faithfully but placed the *call* where the port placed it. It agreed
with the port's wrong window and reported an exact match. Only running
the activations caught it. **A replay has to reproduce the call site,
not just the callee.**

### Stage 7 — the CLI and the point cloud (`src/main.nu`)

`lingbot-map --help` has the current surface; the README has the
examples. What matters here is what happens between the frames and the
file.

Each frame goes through preprocessing, the DINOv2 trunk and the
streaming aggregator — which keeps its KV cache across frames, so the
poses land in one shared world frame — then the camera head for a pose
and the DPT head for depth and confidence. Depth plus intrinsics plus
the camera-to-world transform unprojects to world points, which is the
cloud.

`world_points` matches the reference's own
`unproject_depth_map_to_point_map` to **1.5e-6**, and is checked as part
of the end-to-end test rather than assumed from the depth agreeing.

Two things about the geometry are easy to get wrong and are worth
stating, because both are silent:

* The reference builds its pixel grid with `np.arange(W)` — **integer**
  pixel coordinates, not sample centres. Half a pixel of offset is not
  visible in any single number.
* `unproject_depth_map_to_point_map` takes the **world-from-camera**
  extrinsic that the pose encoding decodes to and inverts it itself.
  Handing it the already-inverted one gives a plausible-looking cloud
  that is in the wrong frame.

Output is `binary_little_endian` PLY, which every viewer reads, with
`--ascii` for the text form. Binary is the default because ASCII is not
a rounding cost here: formatting three coordinates per point ran at
15 us a point, 470 ms a frame at the default stride — more than the
depth head. The two forms select the same points; the binary one stores
each coordinate as the f32 it came from rather than the shortest
round-tripping decimal, so they agree to 6e-8. The end-to-end test writes
both and checks it.

The vertex count is not known until the last frame is done, so the
header is written with a fixed-width zero-padded placeholder and patched
by seeking back at the end — the alternative is holding the whole cloud
in memory, and a 300-frame sequence is tens of millions of points.
Points are flushed a row at a time.

On two consecutive courthouse frames at the defaults: 61 458 points,
frame centroids 0.0095 apart in a scene 2.82 across — the two frames
land on top of each other, which is what a shared world frame means.

### Stage 5 — the DPT depth head (`src/dpthead.nu`)

Loads and runs end to end in ~150 s and matches the reference: `depth`
to **1.6e-6** and `depth_conf` to **7.8e-6**, with every intermediate —
the token norm, the four projections, the position embedding, all four
resize layers (both ConvTransposes and the strided conv), the four
`layerN_rn` reductions, all four fusion blocks and `output_conv1` —
inside 5e-6.

Getting there took a bisect worth writing down, because the bug was
invisible to everything except the reference itself.

The divergence started at `dpt_f4`, the first fusion block, at a scaled
error of 6.8e+2. Every stage before it was already correct to float32
noise. Three things were ruled out in turn:

* **The ops.** `tests/fusecheck.nu` runs one fusion block on synthetic
  weights at 8×3×5 — seconds instead of 150 — and `resConfUnit2`, the
  bilinear upsample and the 1×1 `out_conv` each matched.
* **The plumbing.** The real head keeps its blocks in a `Vec DpFuse`,
  36 scalars deep, and pulls them out by index through an `Option`
  match. Four blocks with distinguishable weights came back correct.
* **The weights.** Every DPT tensor read through `Lw` matched torch's
  sum and absolute maximum exactly.

Right input, right ops, right plumbing, right weights, wrong output.
What broke the deadlock was strengthening the dumps: a strided sample of
a 53 504-element tensor is six numbers, and six numbers can agree while
the tensor does not, so `__dp_dump` and the oracle's DPT trace both
gained a whole-tensor sum and absolute maximum. That confirmed the input
was right over every element, and — once probes went *inside* the block
— that the reference's `resConfUnit2` takes an input peaking at 974 and
returns one peaking at **0.144**, while the port returned its input
essentially unchanged.

No residual unit of the form `x + g(x)` can do that. The reference's is
not that form:

```python
self.activation = nn.ReLU(inplace=True)   # _make_fusion_block
...
out = self.activation(x)      # OVERWRITES x
out = self.conv1(out); out = self.activation(out); out = self.conv2(out)
return self.skip_add.add(out, x)          # x is relu(x) by now
```

The residual added back is `relu(x)`, not `x`. The input to refinenet4
averages −473, so clipping it is the whole point — and adding back the
original `x` instead leaves that entire negative bulk in the output.
Nothing fails, no shape is wrong, no weight is missing; the depth map is
just wrong by three orders of magnitude.

The lesson is about the oracle, not the language. `tests/fuse_oracle.py`
originally re-implemented the block from a *reading* of the reference
source and reproduced the same misreading, so the unit test passed while
the head was wrong. It now imports `_make_fusion_block` and drives the
reference's own module, which cannot drift from it.

The bisect harness is kept:

* `LINGBOT_DPT_TRACE=1 tests/agg_oracle.py …` re-walks the reference
  head's own submodules and dumps every stage: `dpt_proj_N`,
  `dpt_pos_N`, `dpt_rs_N`, `dpt_rn_N`, `dpt_rcu4`, `dpt_up4`,
  `dpt_f4..f1`, `dpt_oc1`, each with a whole-tensor sum and absmax.
* `dp_forward`'s `trace` argument prints the same stages from the port,
  in the same format, so a single run localises the divergence. A
  150 s forward is not something to bisect by adding one print at a
  time.

The reference stage values are recorded below for orientation; note how
large `dpt_rs_3` and `dpt_rn_3` legitimately get (−170 … −447), which
is *not* the bug.

The shapes below are read off the real checkpoint:

| piece | shape | note |
|---|---|---|
| `norm` | LayerNorm(2048) | over the tapped tokens, patches only (from index 6) |
| `projects.0..3` | 1×1 conv 2048 → **256, 512, 1024, 1024** | one per tapped layer; the four differ |
| `resize_layers.0` | ConvTranspose2d 256→256, k4 s4 | ×4 up |
| `resize_layers.1` | ConvTranspose2d 512→512, k2 s2 | ×2 up |
| `resize_layers.2` | Identity | — |
| `resize_layers.3` | Conv2d 1024→1024, k3 s2 p1 | ×2 down |
| `scratch.layer{1..4}_rn` | 3×3 conv → 256, **no bias** | 256/512/1024/1024 in |
| `scratch.refinenet{1..4}` | fusion blocks | refinenet4 has **no** `resConfUnit1` |
| `scratch.output_conv1` | 3×3 conv 256 → 128 | |
| `scratch.output_conv2` | 3×3 conv 128→32, ReLU, 1×1 conv 32→**2** | depth + confidence |

Config: `intermediate_layer_idx = [0,1,2,3]`, `pos_embed=True`,
`activation="exp"`, `conf_activation="expp1"`.

`gkd_resize_bilinear` was added to gpukit for this (both corner
conventions, verified against torch); `gkd_conv2d` and
`gkd_convtranspose2d` already existed. `gkd_convtranspose2d` indexes its
weight as `[cin, cout, kh, kw]`, which is PyTorch's ConvTranspose2d
layout — checked, and not the bug.

Also needed: `_apply_pos_embed`, which builds a UV grid and a sinusoidal
embedding scaled by 0.1 and adds it **twice** — after each project and
after the final interpolate.

### Stage 5 (partial) — the camera head (`src/camhead.nu`)

**This is where a pose comes out.** It reads one token per frame — the
camera token, row 0 of the last tapped aggregator layer — and refines a
9-vector over four passes:

```
pred ← 0
repeat 4:
    cond               = embed_pose(pred)                9 → 2048
    shift, scale, gate = Linear(SiLU(cond))              2048 → 3·2048
    x                  = gate · (adaLN(tok)·(1+scale) + shift) + tok
    x                  = trunk(x)                        4 blocks, dim 2048
    pred               = pred + pose_branch(trunk_norm(x))
```

A DiT-style adaptive-LayerNorm loop: each pass sees its own previous
answer, so the trunk is asked *what is wrong with this pose* rather than
*what is the pose*.

End to end on the real checkpoint — preprocess, DINOv2, aggregator,
camera head — **106 s, 5.7e-7** against the real model's `pose_enc`, and
the decoded result is what frame 0 should be: identity rotation,
zero translation, fx ≈ 290.8 / fy ≈ 290.9 for a 518×294 frame.

Details that bite:

* the trunk is dim 2048 with 16 heads, so head_dim is **128** and its
  3-D rope splits **40/44/44** — not the 20/22/22 the aggregator's
  64-dim heads use. Same kernel, different geometry, so the axis widths
  are a parameter now.
* `adaln_norm` has **no affine parameters** and eps **1e-6**, while
  `token_norm`, `trunk_norm` and the trunk's own norms are plain
  `nn.LayerNorm` at 1e-5. That is a *fourth* epsilon.
* only the field of view is activated (ReLU — it cannot be negative).
  Translation and quaternion pass through linear, which is why the
  quaternion is never unit and why `src/geom.nu` divides by its own
  squared norm.
* `poseLN_modulation` is `Sequential(SiLU, Linear)`, so the checkpoint
  only carries `.1.weight` / `.1.bias` — element 0 is the SiLU.

### Stage 4 — the aggregator, one frame (`src/aggregator.nu`)

DINOv2's patch tokens, six special tokens prepended, then 24 **frame**
and 24 **global** blocks alternating, with four pairs tapped and
concatenated into [P, 2048] feature maps. On the real checkpoint, for
one 518×294 frame: **103 s, 7.3 GB, 5.4e-6** against the actual model's
four outputs.

That is 909M parameters and 72 transformer blocks agreeing to float32's
noise floor.

Streaming works: `LmKv` holds each global block's keys and values as
`[heads, maxkv, hd]`, each frame appends its rotated k/v at row `kvused`
and attends over everything stored. **Two frames through the cache match
the real model to 5.4e-6** — the same figure as one frame, which is what
a correct cache should give.

`used` is read by the block and never written by it: one frame passes
through 24 separate caches, so the count belongs to the frame and is
passed in per call rather than stored 24 times and kept in step by hand.

One subtlety in the layout: a cache is `[heads, maxkv, hd]` but only
`nkv` rows are live, so a prefix view is **not** contiguous per head.
The live rows are repacked into a tight `[heads, nkv, hd]` before the
permute. Correct, and the obvious thing to make cheaper later.

Cost is close to linear so far: 103 s for one frame, 201 s for two on
the CPU backend. Frame 2 attends over 1566 keys instead of 783 and pays
the repack, and it still comes in at about what frame 1 costs — the
per-frame DINOv2 trunk dominates at this length.

**Eviction is implemented as a ring, not as repeated `torch.cat`** —
see the stage 4 eviction section. Past 72 frames the sliding window is
needed for *correctness*, not just for memory: without it the model
attends to frames the reference has already dropped.

**Three different LayerNorm epsilons in one model**, and getting one
wrong is worth ~1e-3:

| | ε |
|---|---|
| DINOv2's blocks and final norm | 1e-6 |
| aggregator frame/global `norm1`/`norm2` | **1e-5** |
| `q_norm` / `k_norm` everywhere | 1e-5 |

Only `DinoVisionTransformer` passes `partial(LayerNorm, eps=1e-6)` to
its blocks. `Block` and `Attention` both default to plain
`nn.LayerNorm`, so everything the aggregator builds gets 1e-5. Using
1e-6 throughout produced a *constant* 4e-3 absolute error that appeared
in the very first block group and never grew — which is how it was
found: real accumulation grows with depth, a systematic error does not.

### Stage 4 (partial) — the DINOv2 trunk (`src/dino.nu`)

The aggregator's "patch embedding" is a whole frozen 24-block ViT-L/14,
and it now runs on the real checkpoint: **35 s, 2.5 GB, 3.9e-6** against
the actual model's `x_norm_patchtokens` for an example frame.

The token order matters and is easy to get subtly wrong, because the
position embedding is added *in the middle* of building it:

```
[cls] + patches            ← pos_embed added HERE
[cls] + [reg×4] + patches  ← register tokens spliced in AFTER
```

so the four register tokens get no position embedding at all, and the
patch tokens the aggregator wants start at index 5.

`src/load.nu` maps the checkpoint onto device buffers with nothing
transposed — torch stores a `Linear` weight as `[out, in]` and
`gkd_gemm` reads it with `transb=1` — and stages one tensor at a time,
so peak extra memory is the largest single weight (32 MB) rather than
the model.

### Stage 4 (partial) — 3-D RoPE (`src/rope.nu`)

The aggregator's **global** blocks do not use the 2-D rope the frame
blocks use. With `enable_3d_rope` — which is `demo.py`'s default — they
use `WanRotaryPosEmbed`, and it differs on three axes at once:

| | 2-D (frame blocks) | 3-D (global blocks) |
|---|---|---|
| axes | row, column | frame, row, column |
| head split | half / half | 20 / 22 / 22 |
| theta | 100 | 10000 |
| pairs | split each half at half/2 | **interleaved** (x₀,x₁), (x₂,x₃), … |

Same idea, incompatible memory order, and nothing about picking the
wrong one looks wrong. Bit-exact against the real `WanRotaryPosEmbed` —
that test imports the upstream package rather than re-implementing it,
because a hand-written oracle for this would just be a second chance to
make the same mistake.

Token positions are fixed by the layout: special token *j* sits at
`(f, j, j)` and patch `(py, px)` at `(f, 6+py, 6+px)`, so the six
special tokens run down a diagonal that the patch grid never reaches.

### Stage 4 (partial) — the block on the device (`src/devblock.nu`)

The block again, this time in **f32 over gpukit's `gkd_*` ops** — gemm,
layernorm, bmm, softmax, permute, broadcast-elementwise — so the same
code runs on CUDA and on the CPU backend. This is the one that will
actually run the model; `src/block.nu` stays as the reference it is
checked against.

Keeping both is the point. A device block is ~15 kernel launches, every
one with a stride or a permutation that can be silently wrong, and
comparing against one slow implementation that is known correct catches
all of them at once. Measured difference: **3e-6**, which is what f32
accumulation over these sizes should give — against ~9e-2 for the head
stride bug that was in the host version.

Torch's weight layouts are used unchanged: a `Linear` weight is
`[out, in]` and goes straight into `gkd_gemm` with `transb=1`, so
nothing is transposed at load time.

The one kernel that had to be written is 2-D RoPE — the rest of the
block is composition.

### Stage 3 — the transformer block (`src/block.nu`)

The unit this model is 72 of (24 DINOv2 + 24 frame + 24 global):

```
x = x + ls1 · attn(norm1(x))
x = x + ls2 · mlp(norm2(x))
```

pre-norm LayerNorm, LayerScale on both branches, exact (erf) GELU, and
attention that layer-normalises q and k **per head** before rotating
them. Matches the reference to 4e-15.

Two things the reference does that a careful reading still misses:

* **`qk_norm=True` uses a different epsilon.** `Block` builds its
  `Attention` without passing `norm_layer`, so `norm1`/`norm2` get
  DINOv2's `partial(LayerNorm, eps=1e-6)` while `q_norm`/`k_norm` fall
  back to `nn.LayerNorm`'s own default of `1e-5`. Two constants, and
  the port has to carry both.
* q/k/v are `[heads, n, head_dim]`, so a head's stride is `n·head_dim`,
  **not** `n·dim`. Getting that wrong leaves every head past the first
  reading zeros — and attention still produces plausible numbers, so it
  surfaces as a few percent of error rather than as anything obviously
  broken. (It did, here, until the intermediates were dumped.)

`erf` was missing from `stdlib/std/float.nu` and is now there
(`float_erf` / `float_erfc`) — exact GELU needs it, and so does any
normal-distribution CDF.

### Stage 3 — patch embedding (`src/patchembed.nu`)

`Conv2d(3, 1024, kernel=14, stride=14)`. Kernel equals stride, so the
patches do not overlap and the convolution is exactly a matmul: im2col
each 14×14×3 patch into a 588-wide row, multiply by the reshaped
weight. Matches torch's `conv2d` to 4e-15.

im2col is written out rather than fused into the multiply, because the
multiply is what moves to a device kernel later and the layout is what
has to be right first.

### Stage 3 — 2-D RoPE (`src/rope.nu`)

Attention rotates q and k by the token's position in the patch **grid**,
not its index in the sequence: the head dimension splits in half, the
first half rotated by the row coordinate and the second by the column.
Bit-exact against `RotaryPositionEmbedding2D`.

Two things here are silent when wrong: the rotation splits each *half*
at half/2 (not the full head dim at D/2), and `positions` is (row, col)
with row driving the first half — swapping them transposes the model's
idea of the image without changing a single shape.

### Stage 3 — weight access (`src/weights.nu`)

`lw_require` declares the shape a module expects and accumulates
failures, so a mismatched checkpoint names the first thing actually
wrong at load time. Layer counts are read off the file rather than
hard-coded, so the `-long` and `-stage1` checkpoints load too.

## The one that made the reconstruction rubble: the cacheless camera head

Solved, and the hunt is worth keeping because no per-module test could
have found it.

**Symptom.** Each frame's cloud was right — point counts within one part
in 30 000 of the reference, shape correct — and the frames were placed
slightly wrong relative to each other, compounding down the sequence: by
20 frames the centroid sat 1.8e-1 of the scene away, the cloud's scale
wandered between 0.91 and 1.05 of the reference's, and a long walk read
as rubble.

**What was ruled out first, in order.** The arithmetic (one frame agreed
to 2.3e-5); the model's own conditioning (the reference perturbed by
3e-4, the size of the port's activation disagreement, moved only 3.9e-5 —
the port sat 600x further); the depth head (counts matched); and growing
activation error (the aggregator's tapped outputs disagreed by a *flat*
1e-4..6e-4 from frame 1 to frame 10). A non-growing activation error was
producing a growing trajectory error, so the bug had to be downstream of
the activations — and the per-frame centroid stepped from 5.5e-5 to
1.9e-2 exactly at frame 2, the first frame that reads a non-empty cache.

**The bug.** `src/camhead.nu` ran the trunk with `lm_kv_none` and a
comment asserting the cache "only matters once frames accumulate" — every
frame was posed alone, attending to itself. The reference's
`CameraCausalHead` is causal *across frames*: the trunk attends over
every previous frame's camera token, with a **separate KV cache per
refinement pass** — pass i of frame N attends to the pass-i tokens of
frames 0..N, because each pass's tokens are modulated by that pass's own
running prediction. And its eviction guard is `tokens-per-frame > 1`
(`_apply_kv_cache_eviction_causal`), which a one-token-per-frame stream
never satisfies: the camera caches intentionally hold the **entire
trajectory**, unlike the aggregator's evicted ones. That detail is
invisible unless the call site is read — the same lesson the aggregator
eviction taught.

**Why every test passed.** Pose agreement had only ever been checked on
frame 0, where a cacheless head and a causal one are the same
computation, bit for bit. The streaming tests compared aggregator
activations, which were never wrong. Only step 20 — the whole deliverable
over a sequence — could see it, and it is the test that did.

**After the fix** (sixteen caches, 4 passes x 4 blocks, rows appended
after rope at the frame's own position): 20-frame median displacement
3.0e-3 → 2.4e-4, centroid 2.6e-2 → 1.2e-4, per-frame scale 0.9997–1.0003,
and over all 286 courthouse frames the whole cloud matches the reference
at median 2.4e-4 with no growth from frame 2 to frame 286. Frame 0's
pose is unchanged to the digit. Speed is unchanged — the extra attention
is one query row over at most N cached rows, sixteen times a frame.

## Running the tests## Running the tests

```
cd packages/lingbot-map && ./tests/lingbot_map_test.sh
```

**It is slow.** Eleven steps, each with its own NURL build, and the last
two run the model on real weights (35 s for the trunk, 105 s for the
aggregator). Budget ~45 minutes on a CPU. The steps that need the
checkpoint or the upstream package skip cleanly when those are absent,
which is the fast path.

Needs a python with torch (any CPU build) for the oracle; set
`PYTORCH_PY`, or drop a venv at the repo root as `.venv-oracle`. Without
one the oracle steps skip and the code is only smoke-run.

Two steps go further and import the **upstream package** from
`~/dev/lingbot-map` (needs `torch torchvision pillow numpy scipy einops
huggingface_hub`): the 3-D rope check, and `tests/agg_oracle.py`, which
loads the real checkpoint and runs the actual model end to end. That
last one is how `tests/agg_ref_courthouse0.txt` was produced — the
aggregator's four outputs for one example frame, which is the ground
truth the rest of stage 4 is built against. Regenerating it takes the
4.6 GB checkpoint and a few minutes of CPU, so it is committed.

## Notes for whoever picks this up

**Compute.** Most of the port was written with no usable GPU on the
development machine, on gpukit's CPU backend. That made two things
necessary before any model code could be written, both now upstream:

* the CPU backend's matmul was a per-output-element kernel — right on a
  GPU, 24× off the machine on a CPU. It is register-tiled now (1.7 →
  42 GFLOP/s on a 6-core i7-5930K), bit-identical either way.
* `stdlib/ext/zip.nu` could not read zip64 and needed the whole archive
  in memory, so a 4.6 GB checkpoint was simply unopenable.

A frame is roughly 2 TFLOP, so on a CPU expect ~1–2 minutes per frame.
The CPU backend is still worth keeping: it is how `src/devblock.nu` is
checked against `src/block.nu`, and a kernel that disagrees between the
two backends is a kernel bug rather than a porting bug.

**Two resamplers, and the trap between them.** Preprocessing resizes
frames with **PIL's** bicubic; `interpolate_pos_encoding` resamples
DINOv2's 37×37 position grid to the frame's patch grid with **torch's
`bicubic` + `antialias=True`**. Both are implemented and both are
verified — `image_resize_bicubic` and `src/interp.nu`.

The trap is the kernel constant. torch has *two* bicubic
implementations that disagree on it:

| | kernel `a` | arithmetic |
|---|---|---|
| PIL (preprocessing) | −0.5 | 8-bit fixed point, clamped |
| torch `antialias=True` | **−0.5** | float, unclamped |
| torch `antialias=False` | **−0.75** | float, border-replicated |

Every reference to "torch bicubic" means the −0.75 one, and the
antialias path — which is what this model uses — is −0.5, because it
was written to reproduce PIL. Building the position-grid resample from
the documented −0.75 gives a kernel that is a few percent wrong
everywhere and right nowhere, with nothing to notice. (Recovered by
probing torch with unit impulses and solving for `a`: −0.49997.)

**Checkpoint layout.** [`checkpoint.md`](checkpoint.md) is the
full inventory read out of the real 4.6 GB file: every tensor name, dtype
and shape, 1342 of them, 1.16 B parameters, all f32. Worth reading before
writing any of stages 3–5 — a few things are not what the Python source
suggests:

* the root is a **bare `OrderedDict`**, not `{"model": …}`, so names come
  out of `torchpt` unprefixed (`aggregator.frame_blocks.0.attn.qkv.weight`);
* there is **no `point_head`** — `enable_point` is off, which is
  `GCTStream`'s default. World points come from unprojecting the depth
  map, not from a second DPT head;
* `aggregator.patch_embed.pos_embed` is `1×1370×1024` = 1 cls + 37×37
  patches, which is what forces the position-grid resample.
