# lingbot-map — Geometric Context Transformer in pure NURL

A port of [LingBot-Map](https://github.com/robbyant/lingbot-map), the
feed-forward 3D foundation model for **streaming 3D reconstruction**:
feed it a sequence of frames, get back per-frame camera poses, depth
maps and a world-space point cloud, one frame at a time, with no
per-scene optimisation.

**Status: in progress.** The port is staged, and each stage is verified
against the reference PyTorch implementation before the next one starts.
What is done and what is not is spelled out below — nothing here claims
to work that has not been checked against the oracle.

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
| 1 | read the `.pt` checkpoint | **done** — [`torchpt`](../torchpt); the real 4.6 GB file in 0.01 s / 31 MB RSS, values identical to `torch.load` |
| 2 | image loading and preprocessing | **done** — byte-identical to the reference pipeline on real frames |
| 3 | ViT layers: patch embed, 2-D RoPE, qk-norm attention, block | **done** — the full block matches the reference to 4e-15 |
| 4 | streaming aggregator + KV cache | **single frame end-to-end on real weights** — all 72 blocks, 5.4e-6 vs the real model. Multi-frame KV cache pending |
| 5 | camera head, DPT heads | pending |
| 6 | camera geometry | **done** — matches torch to 2.4e-16 |
| 7 | CLI, point-cloud export, end-to-end check | pending |

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

### Stage 4 — the aggregator, one frame (`src/aggregator.nu`)

DINOv2's patch tokens, six special tokens prepended, then 24 **frame**
and 24 **global** blocks alternating, with four pairs tapped and
concatenated into [P, 2048] feature maps. On the real checkpoint, for
one 518×294 frame: **103 s, 7.3 GB, 5.4e-6** against the actual model's
four outputs.

That is 909M parameters and 72 transformer blocks agreeing to float32's
noise floor.

Single frame so far. With no cache the global blocks attend to their own
frame's tokens, which is exactly what the reference does on frame 0;
frames 2+ need the KV cache and its sliding-window eviction.

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

## Running the tests

```
cd packages/lingbot-map && ./tests/lingbot_map_test.sh
```

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

**Compute.** There is no usable GPU on the development machine, so the
port runs on gpukit's CPU backend. That made two things necessary before
any model code could be written, both now upstream:

* the CPU backend's matmul was a per-output-element kernel — right on a
  GPU, 24× off the machine on a CPU. It is register-tiled now (1.7 →
  42 GFLOP/s on a 6-core i7-5930K), bit-identical either way.
* `stdlib/ext/zip.nu` could not read zip64 and needed the whole archive
  in memory, so a 4.6 GB checkpoint was simply unopenable.

A frame is roughly 2 TFLOP, so expect ~1–2 minutes per frame on a CPU
and design the CLI around that (stream, checkpoint, resume) rather than
around interactive use.

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

**Checkpoint layout.** [`docs/checkpoint.md`](docs/checkpoint.md) is the
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
