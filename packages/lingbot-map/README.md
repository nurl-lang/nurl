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
| 1 | read the `.pt` checkpoint | **done** — see [`torchpt`](../torchpt), verified against `torch.load` |
| 2 | image loading and preprocessing | **done** — byte-identical to the reference pipeline on real frames |
| 3 | ViT layers: patch embed, 2-D RoPE, qk-norm attention, block | position-grid resample and 2-D RoPE **done**; patch embed, attention, block pending |
| 4 | streaming aggregator + KV cache | pending |
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

### Stage 3 (partial) — 2-D RoPE (`src/rope.nu`)

Attention rotates q and k by the token's position in the patch **grid**,
not its index in the sequence: the head dimension splits in half, the
first half rotated by the row coordinate and the second by the column.
Bit-exact against `RotaryPositionEmbedding2D`.

Two things here are silent when wrong: the rotation splits each *half*
at half/2 (not the full head dim at D/2), and `positions` is (row, col)
with row driving the first half — swapping them transposes the model's
idea of the image without changing a single shape.

### Stage 3 (partial) — weight access (`src/weights.nu`)

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
