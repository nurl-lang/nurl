# Changelog

## 0.8.0

**The PLY writer, the viewer and the video extractor are their own
packages.** `src/video.nu` is now the `video` package (MJPEG-AVI frame
extraction in pure NURL, ffmpeg fallback), and the PLY section of
`src/main.nu` plus `src/viewer.nu` / `views/viewer.html` are now the
`ply` package (streaming writer with the patched vertex count, the
embedded WebGL viewer, `vw_serve`). Both were general-purpose code that
had nothing lingbot-shaped in them; they now version and improve on
their own, and this package consumes them as ordinary dependencies.

Behaviour is unchanged — same flags, same output bytes, same viewer —
with one visible exception: the viewer page's title is now "ply viewer"
rather than "lingbot-map viewer" (the HUD names the cloud being shown,
as before). The PLY comment line still says `lingbot-map, pure NURL`.

## 0.7.0

**A run that cannot fit says so, with the numbers.** A phone video is
portrait, a portrait frame crops to 518x518 = 1375 tokens against a
landscape frame's 783, and past the 72-frame window the KV caches want
~1.75x the memory — on a 24 GB card, 111 portrait frames need 19.0 GB of
cache with ~18.7 GB free once the checkpoint is resident. Through 0.6.0
that failed as three bare lines:

    lingbot-map: aggregator failed
    lingbot-map: camera head failed
    lingbot-map: depth head failed

— the first because a device allocation failed without saying so, the
other two because the stage messages printed even for stages that were
skipped. Now the run is costed BEFORE the first allocation:

    lingbot-map: this run does not fit on the device.
      frames        111 of 518x518 = 1375 tokens each
      caches need   19.0 GB
      device free   18.7 GB of 23.5 GB
    Ways to fit:
      --image-size 392   fewer tokens per frame (392 = 28 patches)
      --stride 2         half the frames
      --max-frames N     reconstruct a shorter stretch

**`--image-size N`** (and the reference's `--image_size`) is the real
resolution lever: the input width, a multiple of 14, default 518.
Smaller means fewer tokens and a smaller cache — 392 fits the same 111
portrait frames on the same card, and completes them in 41 s. The model
handles the size at runtime through the position-grid resample; notably
the reference's own `--image_size` flag cannot actually do this (a
GCTStream built at another size rejects the checkpoint — pos_embed 1370
vs 785 rows), so the comparison harness drives the reference the only
way that works: build at 518, preprocess at the requested size.

Verified against the reference at 392 on portrait frames: median
5.9e-4, point counts within 0.04%, VERDICT match.

Stage messages now name only the stage that actually failed. Needs
gpukit 0.6.2 (`gk_mem_free`/`gk_mem_total`, backed by `cuMemGetInfo` on
CUDA and /proc/meminfo on the CPU backends — gpu 0.11.1). The preproc
oracle now includes a portrait frame, which the crop path had never been
tested with.

## 0.6.0

**Video input.** Shoot a video, hand the file over:

    lingbot-map --view walk.mp4
    lingbot-map --fps 5 walk.avi

Frames are extracted into `<video>_frames/` next to the file — the same
place `demo.py` leaves them — and then the ordinary pipeline runs, so
`--max-frames`, `--stride` and everything else apply to a video
unchanged. `--fps` (default 10) samples the stream by its own frame
rate: every `round(src_fps / fps)`-th frame, the arithmetic `demo.py`
uses.

Two decode paths, deliberately:

- **MJPEG in AVI is parsed by lingbot-map itself, in pure NURL.** An AVI
  is a RIFF tree and an MJPEG chunk is a complete JPEG, which
  `packages/image` already decodes — extraction is a container walk, not
  a codec. Cameras, OBS and ffmpeg can all record MJPEG.
- **Everything else** (H.264, HEVC, VP9, ...) delegates to `ffmpeg` when
  it is on PATH — a from-scratch H.264 decoder is not this package's
  fight, and the reference makes the same call by shelling out to
  OpenCV. Without ffmpeg the error says exactly what to install or how
  to record instead.

Re-extraction replaces the previous frames rather than mixing with them,
so a shorter run cannot inherit a longer one's tail. Verified end to
end: the reference run on the same extracted JPEGs agrees with the
port's video-input cloud at median 2.9e-4 (VERDICT match) — the video
path adds nothing beyond the JPEG encode itself. Suite step 22 builds an
MJPEG AVI from scratch (`tests/make_avi.py`, Pillow + struct, no
ffmpeg) and checks the fps stride, the files and the replacement
behaviour, with no checkpoint and no GPU.

## 0.5.0

**The reconstruction holds together now.** Through 0.4.x each frame's
cloud was correct on its own and the frames were placed slightly wrong
relative to each other, compounding down the sequence — by 20 frames the
centroid sat 1.8e-1 of the scene's own scale away, and a long walk read
as rubble rather than a street.

The camera head was running **cacheless**: every frame's pose was
estimated from that frame's camera token alone, attending to itself. The
reference's `CameraCausalHead` is causal *across frames* — the trunk
attends over every previous frame's camera token, with a separate KV
cache per refinement pass (pass i of frame N attends to the pass-i
tokens of frames 0..N), and its eviction guard is `tokens-per-frame > 1`,
which a one-token-per-frame stream never satisfies, so those caches
intentionally hold the entire trajectory. The port now does exactly
that: sixteen caches (4 passes x 4 trunk blocks), rows appended after
rope at the frame's own position, attention over the full prefix.

Measured over the whole deliverable, same frames, same checkpoint:

| | 0.4.x | 0.5.0 |
|---|---:|---:|
| 20-frame median displacement | 3.0e-3 | **2.4e-4** |
| 20-frame centroid drift | 2.6e-2 | **1.2e-4** |
| per-frame scale vs reference | 0.91-1.05 | **0.9997-1.0003** |
| error growth down the sequence | compounds | **flat** |

Frame 0's pose is bit-for-bit what it was (2.3e-7 vs the reference) —
a cacheless head and a causal one are the same thing for one frame,
which is also why the per-frame test suite never caught this. Step 20's
sequence tolerance tightens from 5e-3 to 1e-3 accordingly.

The viewer gains a `roll` URL parameter alongside
`yaw/pitch/dist/ps/trim`: the world frame is the first camera's, and a
hand-held first frame is rarely level, so orbiting alone cannot square a
tilted scene. The README's image is regenerated from the fixed
reconstruction with the exact parameters in its caption. No format
changes; the PLY is as in 0.4.2.

## 0.4.2

**The viewer looked like it hung, at every cloud size.** The cloud
downloaded, the message changed to "building the point buffer...", and
that is where it stayed — for ever. Reported from a real browser; every
automated check had been passing throughout.

The cloud was in fact loading and rendering perfectly the whole time,
behind an opaque overlay that never went away. `el.hidden = true` sets an
attribute, and the UA stylesheet turns that into `display: none` with a
plain type selector — which **any** author rule outranks. `#status` set
`display: grid`, an ID rule, so it won. The loading screen stayed on top
of a finished render at `z-index: 5`.

One line fixes it, and every page should carry it:

```css
[hidden] { display: none !important; }
```

**Two things about how this got missed, because they are the real
lesson.** The render check reads the GL framebuffer with `gl.readPixels`,
so it saw a perfect cloud and never saw the DOM stacked on top of it — it
answers "did the GPU draw", not "can a person see it". And when Chrome's
`--screenshot` kept returning the loading screen while `--dump-dom`
showed the page settled with 590 002 points parsed, that was diagnosed as
a stale compositor frame in Chrome. It was not. The screenshot was
photographing the actual bug, faithfully, every time; the DOM check was
reading the `hidden` attribute, which was the one thing that was true and
meaningless. The comments and notes that blamed Chrome are corrected.

`tests/viewer_shot.sh` now also asserts the overlay's **computed**
`display` is `none`, which is the thing the attribute could not tell it.
Verified against a copy of the 0.4.1 page: it fails with `the loading
overlay is still VISIBLE (display: grid)` while simultaneously reporting
138 304 lit pixels — the exact shape of the bug.

## 0.4.1

**0.4.0 printed the wrong version.** `--version` said `lingbot-map 0.3.0`
on a binary that had the viewer in it: the string lives in `src/main.nu`,
the real version lives in `nurl.toml`, and bumping one did not touch the
other. Nothing anywhere compared them, so it published clean and only
turned up when the installed 0.4.0 was asked what it was.

Fixed, and the suite now compares the two — a version that disagrees with
the manifest fails the build rather than shipping.

Also here: the README shows what the viewer actually looks like
([`docs/viewer.png`](docs/viewer.png), 286 frames of the courthouse walk)
and spells out how to open it — the command, the address it prints, and
what every control does. The viewer takes `?yaw=&pitch=&dist=&ps=&trim=`
so a particular view can be linked to.

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
