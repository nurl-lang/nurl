# Changelog

## 0.4.0

**You can look at the output now.** The reference's `demo.py` ends in a
viser web viewer; this ended in a PLY and the advice to bring your own.

- **`lingbot-map view cloud.ply`** serves a viewer on
  `http://127.0.0.1:8080`: drag to orbit, wheel to zoom, shift-drag to
  pan. One self-contained HTML page drawing the cloud through WebGL —
  no CDN, no dependency, nothing fetched from anywhere. It is compiled
  into the binary, so an installed tool needs no files beside it.
- **`--view`** goes from frames to a viewer in one command, opening it
  the moment the cloud is written, which is what `demo.py` does.
- **Trim far points** is the control that matters, and it defaults to
  hiding the farthest 2%: on every example scene that is sky the depth
  head placed a long way off, and it is the difference between a legible
  first frame and a white wall. **Density** thins the cloud on a slow
  machine — the points are shuffled once on load, so any fraction of them
  is a sample of the whole scene rather than the start of the walk.
  **Colour** switches between the frames' own RGB, height and distance.
- Reads any `lingbot-map` PLY, binary or `--ascii`.

One thing worth writing down, because it is silent when wrong: the model
works in OpenCV camera axes, where **y points down**. A viewer that
assumes y-up renders the reconstruction upside down with the sky
underneath it — which looks wrong, but not obviously so. The reference
does the same thing with `up_dir = -R[:, 1]`.

Suite step 21 serves a synthetic cloud, renders it in a real headless
browser and counts lit pixels. It needs no checkpoint, no GPU and no
torch, and it exists because a viewer whose HUD reports half a million
points over an empty canvas is indistinguishable from a working one in
the DOM.

## 0.3.0

The model was right and the front door was not. `lingbot-map --model
<ckpt>` printed the usage and left the reader to work out which line
applied to them; this is the release where the command explains itself.

- **`lingbot-map <frames-dir>` is the whole command.** A directory as a
  positional argument is the frames; `--model` is now optional and
  resolves through [hub](../hub) — `$LINGBOT_MAP_MODEL`, else
  `~/.nurl/models/lingbot-map/lingbot-map.pt`, else
  `robbyant/lingbot-map/lingbot-map.pt` is fetched once and cached. A
  Hugging Face ref works as `--model` too.
- **Errors name what is wrong.** No frames, an unknown option, a missing
  value, a frame that does not exist, a directory with nothing in it —
  each says so and shows the command that would have worked, instead of
  reprinting the usage. `--help` is a real help page with examples and
  exits 0; `--version` was missing entirely.
- **A mistyped option is an error**, not a frame filename that fails
  much later as a missing file. Frame paths are all checked *before* the
  4.6 GB checkpoint is read, so a typo costs nothing.
- **The reference's spellings are accepted** — `--model_path`,
  `--image_folder`, `--conf_threshold`, `--first_k` — so a `demo.py`
  command line mostly transfers.
- **`--stride <n>`**, the reference's own frame subsampling, which had no
  equivalent here: `--stride 20` reconstructs a 286-frame walk from 15
  frames in 4 s. It applies *after* `--max-frames`, in the order
  `demo.py` applies `--first_k` and `--stride`, so thirty frames at a
  stride of three is ten.
- **`--conf` defaults to 1.5**, which is `demo.py`'s own
  `--conf_threshold`. It was 2.0, described in a comment as the
  reference's default, which it is not. At the same threshold the cloud
  is byte-for-byte what 0.2.1 produced.
- **Frame directories are listed with `dir_list`, not `fs_glob`.** The
  glob did not descend through a symlinked directory, so pointing at a
  linked frame folder reported "no .png or .jpg" and stopped. `.jpeg` is
  recognised now, and the extension match is case-insensitive. Each
  directory is sorted on its own before being appended, so naming two of
  them keeps them in the order given.
- **The run says what it is doing**: the checkpoint it chose, the frame
  count and the output path up front, and frames, points and elapsed time
  at the end.
- The README is now about using it. The porting war stories moved to
  [`docs/porting-notes.md`](docs/porting-notes.md) intact.

No change to the model, the kernels or the numerics.

**And one thing that is not a feature.** Turning "as fast as the
reference" into a measurement — `tests/ref_cloud.py` drives
`~/dev/lingbot-map` through its own `inference_streaming` and writes the
same cloud, `tests/cmp_cloud.py` compares them, and both are step 20 of
the suite — turned up something the per-module tests cannot see:

- **The port is 3.4–9.2x faster end to end**, mostly because the 4.6 GB
  checkpoint reads in 1.6 s against `torch.load`'s ~12.6 s. On inference
  alone the two are within about 5%.
- **One frame agrees to 2.3e-5.** Over a sequence the reconstruction
  drifts: by 20 frames the centroid is 1.8e-1 of the scene's own scale
  away and the cloud is ~9% smaller. The depth is right — point counts
  agree to one part in 30 000 — and the poses are not.
- **That drift is not the arithmetic.** Perturbing the reference's input
  by 3e-4, the size of the port's own activation-level disagreement,
  moves the reference's 20-frame cloud by 3.9e-5. The port is ~600x
  further away than the model's conditioning explains.
- Separately, `demo.py` runs the first 8 frames as one bidirectional
  block (`--num_scale_frames`); the port is causal from frame 0, which is
  worth 3.3% of the cloud on 12 frames.

Neither is a regression — both predate 0.2.0 — and neither is fixed here.
They are now measured, written down in the README under "How close is it
really", and pinned by a test, which is the prerequisite for fixing them.

## 0.2.1

- **Parity.** 0.2.0 shipped without the two gpukit kernels that close the
  last of the gap — the retiled fused attention and the shape-specialised
  convolution — because the commit carrying them missed the merge. With
  gpukit 0.6.1 the comparable slice is **138 ms a frame against the
  reference's 141**, f32 on both sides, where 0.2.0 was 172 ms. Requires
  gpukit `^0.6.1`; no source change here beyond the requirement and the
  README's numbers.

## 0.2.0

The port was correct and slow; this is the release where it is fast.
Measured on an RTX 4090 in f32, model load excluded on both sides, it is
**at parity with the reference**: 138 ms a frame against its 141, ahead
on the camera head (16 ms vs 54) and behind on the aggregator and depth
head. End to end, eight frames went **38.2 s -> 3.2 s** and the 4.6 GB
checkpoint load 25 s -> 1.6 s.

Almost all of the work landed in [gpukit](../gpukit) 0.6.0 and
[gpu](../gpu) 0.11.0, because every gap this hit is one any GPU package
hits — a tiled GEMM, fused attention, a caching device allocator,
per-kernel profiling. What is here:

- **The checkpoint is read straight into device memory.** The load path
  widened every f32 weight to f64, transposed the four hot Linear
  weights on the host with a column-strided write per element, and
  narrowed them again on upload. Now the mapped bytes go to the device
  as they are and the transpose is a permute kernel.
- **Two per-frame constants are built once.** The DPT
  positional-embedding grid is a pure function of (channels, height,
  width, aspect) — rebuilding it was ~10 million host `sin`/`cos` a
  frame. The DINOv2 position grid is a bicubic resample over 1024
  channels and a pure function of (gh, gw) — another 53 ms a frame.
  Together a third of the frame, both bit-identical.
- **Binary PLY by default**, `--ascii` for the text form. Formatting
  three coordinates per point cost 15 us a point — 470 ms a frame at the
  default stride, more than the depth head. The end-to-end test checks
  both formats agree.
- **`--profile`** prints per-stage frame timings and the kernel profile.
- **`--frames` and the device choice**: the run opens the strongest GPU
  on the box rather than ordinal 0, which on a machine with an old card
  beside a new one is whichever the driver enumerated first.

Numerics are unchanged or better: 18/18 against the real model, with the
aggregator at 5.291e-6 and the end-to-end depth at 1.505e-5. Everything
except the fused attention is bit-identical to the 0.1.0 kernels — the
`depthcheck` dump is byte-for-byte what a pristine 0.1.0 build produces.

## 0.1.0

First release: the Geometric Context Transformer end to end in pure
NURL — checkpoint reader, preprocessing, DINOv2 trunk, streaming
aggregator with a sliding-window KV cache, camera head, DPT depth head,
geometry, and a CLI that writes a point cloud. Every stage checked
against the reference PyTorch implementation.
