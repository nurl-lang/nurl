# lingbot-map

Streaming 3-D reconstruction, in pure NURL. Hand it a folder of video
frames; it hands back a world-space point cloud, plus a camera pose and a
depth map for every frame — one frame at a time, no per-scene
optimisation, no structure-from-motion pass.

It is a port of [LingBot-Map](https://github.com/robbyant/lingbot-map),
the feed-forward 3-D foundation model, and it runs the same 1.16 B
parameter checkpoint the reference does. Every stage is checked against
the reference PyTorch implementation, and on the same GPU it is several
times faster end to end. On a single frame it reproduces the reference to
2e-5; over a long sequence it drifts, which is measured and quantified
under [How close is it really](#how-close-is-it-really) rather than
glossed.

## Install

```
nurlpkg install lingbot-map
```

## Reconstruct something

```
lingbot-map my-frames/
```

That is the whole command: a folder of `.png` or `.jpg` frames in, a
point cloud out. The first run downloads the 4.6 GB checkpoint from
Hugging Face and caches it under `~/.nurl/models`; every run after that
starts straight away.

```
frames 286 -> cloud.ply
model  /home/wau/.nurl/models/lingbot-map/lingbot-map.pt
frame 1/286  33025 points  526 ms  .../courthouse/000000.png
frame 2/286  66564 points  157 ms  .../courthouse/000001.png
frame 3/286  98930 points  158 ms  .../courthouse/000002.png
...
frame 286/286  8602925 points  410 ms  .../courthouse/000285.png
wrote 8602925 points to cloud.ply  (286 frames, 108624 ms)
```

## Look at it

```
lingbot-map view cloud.ply
```

That serves a viewer on `http://127.0.0.1:8080` — drag to orbit, wheel to
zoom, shift-drag to pan. It is one self-contained page drawing the cloud
on the GPU through WebGL; nothing is fetched from anywhere, and there is
nothing to install.

To go straight from frames to a viewer the way `demo.py` does, add
`--view` and it opens as soon as the cloud is written:

```
lingbot-map --view my-frames/
```

The controls that matter are **trim far points**, which hides the
farthest few percent (almost always sky the depth head placed a long way
off, and it is what makes the first frame legible), **density**, which
thins the cloud on a slow machine, and **colour**, which switches between
the frames' own RGB, height and distance.

`cloud.ply` is an ordinary PLY, so MeshLab, CloudCompare, Blender and
`f3d cloud.ply` open it too.

## Where frames come from

Any folder of `.png`, `.jpg` or `.jpeg` files whose names sort into the
order they were shot. From a video, that is one `ffmpeg` call:

```bash
mkdir frames && ffmpeg -i walk.mp4 -r 10 frames/%06d.png
lingbot-map frames/
```

The example sequences the reference uses — `courthouse`, `loop`,
`university` — come with
[its repository](https://github.com/robbyant/lingbot-map), under
`example/`. Everything below uses one of those, so the numbers are
reproducible.

## More things to try

```bash
# a quick look first: 30 frames instead of all 286
lingbot-map --max-frames 30 ~/dev/lingbot-map/example/courthouse

# the whole walk, but every 20th frame — 15 frames, 4 s
lingbot-map --stride 20 --out sparse.ply ~/dev/lingbot-map/example/courthouse

# every pixel rather than every second one — 4x the points
lingbot-map --pixel-stride 1 --out dense.ply ~/dev/lingbot-map/example/courthouse

# keep more of the uncertain geometry (1.0 is "the model knows nothing")
lingbot-map --conf 1.2 --out loose.ply ~/dev/lingbot-map/example/courthouse

# a checkpoint you already downloaded, and where the time goes
lingbot-map --model ./lingbot-map.pt --profile ~/dev/lingbot-map/example/courthouse

# a few individual frames, in the order you name them
lingbot-map shot0.png shot1.png shot2.png

# a text PLY, for reading with your eyes
lingbot-map --ascii --max-frames 2 --out two.ply ~/dev/lingbot-map/example/courthouse
```

## Options

| | |
|---|---|
| `--model <path\|ref>` | checkpoint to run: a local `.pt`, or a Hugging Face ref such as `robbyant/lingbot-map/lingbot-map.pt`. Default: `$LINGBOT_MAP_MODEL`, else `~/.nurl/models/lingbot-map/lingbot-map.pt`, else that ref is fetched |
| `--out <file.ply>` | where to write the cloud (default `cloud.ply`) |
| `--conf <f>` | keep pixels whose confidence exceeds this (default 1.5, the reference's own `--conf_threshold`) |
| `--pixel-stride <n>` | take every nth pixel on both axes (default 2) |
| `--max-frames <n>` | stop after n frames |
| `--stride <n>` | use every nth frame, applied after `--max-frames` |
| `--frames <dir>` | a directory of frames; the same as naming it positionally |
| `--ascii` | write an ASCII PLY instead of `binary_little_endian` |
| `--quiet`, `-q` | no per-frame progress |
| `--profile` | per-stage frame timings and a per-kernel GPU profile |
| `--view` | open the viewer on the cloud once it is written |
| `--port <n>` | viewer port (default 8080) |
| `--version`, `--help` | |

The reference's own spellings work too — `--model_path`,
`--image_folder`, `--conf_threshold`, `--first_k` — so a `demo.py`
command line mostly transfers.

**Order is the trajectory.** Frames are read in name order, and the model
keeps a cache across frames, so each one is placed relative to the ones
before it. A shuffled directory reconstructs a different scene.

## How it differs from `demo.py`

The model is the same and the numbers agree; the packaging does not.

* **The viewer is a point cloud, not a scene inspector.** `demo.py` ends
  in a viser viewer with camera frusta, per-frame playback and a sky mask;
  `lingbot-map view` orbits the cloud and lets you trim and thin it. Both
  run in a browser on localhost.
* **No video input.** `demo.py --video_path` shells out to OpenCV; split
  the video with `ffmpeg` and point at the folder.
* **No scale-frame block.** `demo.py` runs the first `--num_scale_frames`
  (8 by default) frames as **one block with bidirectional attention among
  themselves**, and only then goes frame-by-frame. The port is causal from
  frame 0, which is what `demo.py --num_scale_frames 1` does. Measured on
  12 frames, that alone is worth **3.3% of the cloud** (370 052 points
  against 357 693). Everything in [How close is it
  really](#how-close-is-it-really) compares against the reference driven
  the port's way, so it is a separate gap and is not folded into those
  numbers.
* **Streaming only.** `--mode windowed`, `--keyframe_interval`,
  `--mask_sky` and `--rotate_clockwise_90` have no equivalent here. The
  sliding KV window is what bounds the memory instead of keyframes,
  which is why 286 frames run at a flat 410 ms each; past ~320 frames
  `demo.py` would start dropping to keyframes and this will not.
* **f32 throughout.** `demo.py` casts the aggregator to bf16. In eager
  mode that is *slower* on this card — 155 ms a frame against f32's
  141 — and it is not what the accuracy figures above were measured
  against.

## What you need

* An NVIDIA GPU and the CUDA driver. VRAM goes with the length of the
  sequence, and stops growing once the sliding KV window fills: ~6.8 GB
  for 8 frames, ~10 GB for 30, ~16.4 GB for 286 and for anything longer.
  `--max-frames` caps the sequence, and so caps the memory.
* The 4.6 GB checkpoint, which the first run fetches for you. To fetch it
  yourself: `hub pull robbyant/lingbot-map/lingbot-map.pt`, or download
  `lingbot-map.pt` from
  [huggingface.co/robbyant/lingbot-map](https://huggingface.co/robbyant/lingbot-map)
  and pass `--model <path>`. The `-long` and `-stage1` checkpoints in the
  same repository are read the same way — layer counts come off the file
  rather than from a constant.

No Python and no PyTorch. The kernels are CUDA C compiled at run time
through NVRTC, so the driver (`libcuda`) and `libnvrtc` are what you
need at run time, and nothing at all at build time.

## Speed

An RTX 4090, f32 on both sides, same frames, same checkpoint.
`tests/ref_cloud.py` drives `~/dev/lingbot-map` through its own
`inference_streaming` and writes the same cloud, so this is the whole
command against the whole command, not a module against a module:

| frames | reference | this port | |
| ---: | ---: | ---: | --- |
| 1 | 14.6 s | 1.6 s | **9.2x** |
| 4 | 14.5 s | 2.0 s | **7.1x** |
| 12 | 15.8 s | 3.4 s | **4.6x** |
| 20 | 17.2 s | 5.1 s | **3.4x** |

Most of that is the checkpoint: the port reads 4.6 GB straight into
device memory in 1.6 s where `torch.load` plus `load_state_dict` takes
~12.6 s, and that cost is paid once however long the sequence. On
inference alone the two are close — at 20 frames the reference spends
3.7 s and the port about 3.5 s.

Per module, on one frame with the load excluded (`tests/ref_timing.py`,
the same slice `--profile` reports):

| | reference | this port |
| --- | --- | --- |
| aggregator | 77 ms | 100 ms |
| camera head | 54 ms | **16 ms** |
| depth head | 10 ms | 22 ms |
| **one frame** | **141 ms** | **138 ms** |

Ahead on the camera head, behind on the other two, and the sum lands
where the reference's does. End to end, including the 1.6 s checkpoint
load, eight frames take 2.8 s, thirty take 7.5 s and all 286 take 109 s.

A frame costs more the more of the sequence it has to attend to, and then
stops: 157 ms at frame 2, 400 ms by frame 73, and 410 ms at frame 286.
That plateau is the sliding KV window filling up — past 72 frames the
model attends over a bounded cache, so the per-frame cost is flat however
long the walk is.

The reference here is torch in eager mode, which is what `ref_timing.py`
measures on both sides. `demo.py` can also turn on `torch.compile` and
CUDA graphs; that is a faster reference this has not been measured
against.

`--profile` shows where a frame goes, and which kernels it spends it in:

```
prep 33 ms  aggregator 100 ms  camera 16 ms  depth 22 ms  cloud 1 ms
  44%  gk32_gemm_smem     1152 calls    201 us each
  11%  gk32_attn64_32      288 calls    206 us
   9%  gk32_gemv           304 calls    156 us
   7%  gk32_lnormrow       760 calls     53 us
```

## Accuracy

Every stage is checked against the reference itself. Where an oracle can
import the upstream module and drive it, it does, rather than working
from a second reading of the source — a hand-written oracle is just
another chance to make the same mistake, and once did.

These are what the suite prints, worst relative error in each case:

| stage | vs the reference |
|---|---|
| frame preprocessing | identical, every value |
| the `.pt` checkpoint, 1342 tensors | identical to `torch.load` |
| 2-D and 3-D rotary embeddings | 0 |
| patch embedding, one transformer block | 4.4e-15 |
| camera geometry | 2.4e-16 |
| DINOv2 trunk, on a real frame | 6.5e-6 |
| the whole aggregator, four tapped layers | 5.3e-6 |
| two frames through the KV cache | 5.3e-6 |
| KV eviction, 120 frames | 0 |
| eviction against the real model, past the window | 9.3e-6 |
| camera pose, after four refinement passes | 2.3e-7 |
| depth, confidence and world points, end to end | 1.5e-5 |

f32 on both sides. The 1e-6-and-up figures are float32's own noise
accumulating over 72 transformer blocks; the ones near 1e-15 are stages
short enough that nothing accumulates.

**Every one of those is a one- or two-frame measurement.** They say the
arithmetic is right. They do not say what a 300-frame reconstruction
looks like, and the next section does.

## How close is it really

`tests/ref_cloud.py` runs `~/dev/lingbot-map` over the same frames and
writes the same cloud; `tests/cmp_cloud.py` asks whether every point of
one has a point of the other in the same place, relative to the size of
the scene. Both are in the suite as step 20.

| frames | point counts | median displacement | centroid drift |
| ---: | --- | ---: | ---: |
| 1 | 33 024 vs 33 025 | 2.3e-5 | 6.9e-5 |
| 2 | identical | 2.3e-4 | 8.9e-3 |
| 4 | 129 979 vs 129 982 | 1.7e-3 | 5.1e-2 |
| 12 | identical | 2.4e-3 | 1.0e-1 |
| 20 | 589 997 vs 590 002 | 3.0e-3 | 1.8e-1 |

So the **depth is right** — the point counts agree to about one part in
30 000, which is the handful of pixels whose confidence sits within f32
noise of the threshold — and the **poses drift**. Each frame's cloud has
the right shape and very nearly the right size; it is placed slightly
wrong, and the error compounds down the sequence.

Some of that is unavoidable in a streaming model: frame N's pose is
estimated from a cache carrying every frame before it, so a small
disagreement early is a larger one later. But not this much. Perturbing
the *reference's* input by 3e-4 — the size of the port's own
activation-level disagreement — moves the reference's own 20-frame cloud
by 4.3e-5 median and 3.9e-5 centroid. The port sits **roughly 600x
further away than the model's own conditioning explains**, so this is a
real accumulating difference in the streaming path and not the arithmetic
being unlucky.

It is not visible to any of the per-module tests above, which is the
point of keeping step 20: the aggregator's activations disagree by a flat
~3e-4 from frame 1 to frame 10 and never grow, while the trajectory built
out of them does. Finding where that turns into pose drift is the open
piece of work on this package.

For a short sequence, or for the shape of a scene rather than its
absolute placement, the port and the reference are the same
reconstruction. For a long walk where the far end has to land in the
right spot, they are not yet.

## How it works

Each frame is resized and cropped to 518 px wide, run through a frozen
DINOv2 ViT-L/14 trunk, then through 24 pairs of transformer blocks that
alternate between attention *within* the frame and causal attention
*across* frames over a KV cache. Four of those pairs are tapped and fed
to two heads: a camera head, which refines a 9-vector pose over four
passes, and a DPT decoder, which gives a depth map and a per-pixel
confidence. Depth plus the pose plus the intrinsics unprojects to
world-space points, and that is the cloud.

The cache is what makes it *streaming*: frame N is placed relative to
every frame before it, so the poses all land in one world frame without
any global optimisation. Past 72 frames a sliding window evicts the
middle of the sequence and keeps the first 8 frames and the last 64,
which is what bounds the memory.

## Tests

```
cd packages/lingbot-map && ./tests/lingbot_map_test.sh
```

Twenty-one steps, each building its own NURL binary. Steps that need the
checkpoint, a python with torch, or the upstream package skip cleanly
when those are absent — that is the fast path, and it is what CI runs.
For the full set, set `PYTORCH_PY` (or drop a venv at the repo root as
`.venv-oracle`) and check out the upstream package at `~/dev/lingbot-map`.

Step 21 renders the viewer in a headless Chrome and needs `google-chrome`
or `chromium` on PATH; it skips cleanly without one and needs no
checkpoint. Step 20, the end-to-end differential, additionally needs a **CUDA** torch —
`.venv-oracle` is deliberately a CPU build, since correctness is all the
other steps need. Set `LINGBOT_CUDA_PY`, or drop one at the repo root as
`.venv-cuda`, and `LINGBOT_CUDA_DEV` if the first CUDA device is not the
one you want.

## Under the hood

[`docs/porting-notes.md`](docs/porting-notes.md) — how the port was
built, every trap that was silent when it was wrong, and what the speed
work actually turned out to be. [`docs/checkpoint.md`](docs/checkpoint.md)
— all 1342 tensors read out of the real file.

Built on [`torchpt`](../torchpt) (reads the `.pt` without executing its
pickle), [`gpukit`](../gpukit) (the kernels) and
[`image`](../image) (PNG/JPEG decode and a PIL-compatible bicubic
resize).
