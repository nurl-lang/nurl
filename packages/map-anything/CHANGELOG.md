# Changelog

## [0.11.0] — 2026-11-23

### Added

- Sharing (recon-kit's): "Share" on a finished job gives a link that opens without
  the sign-in — view and download the cloud and the 3-D object, nothing else.

### Changed

- Sensible limits on the page and in the service: "drop least confident %" 0–50
  (was 0–95), pixel stride 1–4 (was 1–16).

- The service, 3-D objects, voxel fusion and frame choice live in the new
  `recon-kit` package, so other model packages (lingbot-map) offer the same service.
  `map-anything serve` and `map-anything mesh` behave as before; this package keeps
  only what is its own — the option fields its page shows and how they become its
  command line (`src/app.nu`). Its service tests moved to recon-kit, and
  `tests/app_test.sh` checks the options line.
- A pick of files on the upload page now invalidates any older pick's read before it
  can return, so an earlier, slower read can no longer restore a refused selection.

## [0.10.0] — 2026-11-23

### Added

- 3-D objects. `--scene FILE` keeps the views a run emits — each camera as a
  similarity in the point cloud's frame (alignment and window stitch folded
  in), its fitted pinhole, its z-depths, its filtered mask, its colours — and
  `map-anything mesh <scene> -o object.glb [--box x0 y0 z0 x1 y1 z1] [--res N]`
  turns them into a mesh: TSDF fusion inside the box (N cells along its longest
  side, default 256, truncation 4 cells, colour only from views that see the
  surface there), marching tetrahedra (Freudenthal's six per cell: no cracks,
  no case tables), shared edge vertices with interpolated colours, triangles
  turned to face the free space, pieces under 2 % of the largest dropped,
  area-weighted normals, written as binary glTF in glTF's frame (+Y up,
  centred on the box, metres). The whole lego scene meshes in ~2 s on a CPU.
- `serve` keeps every run's views (`scene.bin`) and makes objects as queued
  jobs on the same worker, lock, pid/token and recovery as reconstructions:
  `POST /api/jobs/:id/mesh {box, res}`, `GET /api/jobs/:id/mesh` (state,
  progress, url), `GET /jobs/:id/object.glb`. The cloud viewer opens with a
  region box ("make 3-D object"), and the job list links the object and its
  download. Jobs made before this version say to run them again.
- `tests/mesh_test.sh`: a synthetic scene — a sphere seen by eight cameras with
  exact depths — through the real fusion and extraction: vertices within a cell
  of the sphere, 99.98 % of the normals and 99.86 % of the windings outward,
  the colour through; a bad box and a truncated scene refused.

### Changed

- Requires ply 0.4 (mesh view, region box) and glb 0.1.

## [0.9.0] — 2026-11-22

### Changed

- `--max-views N` keeps N views spread over the WHOLE capture instead of the
  first N, which for a long video was its opening seconds. The frames are split
  into N consecutive runs and each run gives its sharpest frame — the variance
  of the Laplacian of the luminance at 320 px, the classic focus measure — so a
  frame smeared by motion loses its slot to a neighbour (on a 115 s walk, 8 of
  24 runs had a frame over 1.5× sharper than their worst). Photo sets are
  chosen the same way.
- A video with a view budget and no `--fps` is sampled across its whole length:
  three candidates per view, spread evenly (video 0.3's `vid_extract_count`),
  scaled to 1024 px, twice what the model reads. `--fps` (or `--max-views 0`)
  keeps the fixed-rate extraction at full size.
- `serve`: the page's views control is a slider with a number, labelled "frames
  across the video" for a video, and says what it will do — "32 frames spread
  over the whole video, each the sharpest of 3 candidates — one every 2.0 s of
  1 min 5 s", using the length the browser reads from the file. The frames-per-
  second field is gone; "every frame" (0) keeps 2 frames/s.

### Added

- `tests/sharpcheck.nu`: the focus measure ranks a frame well above a blurred
  copy of itself, `sh_pick` keeps the sharp frame of a run, and it times
  `sh_score` (about 70 ms a 1024 px frame).

## [0.8.1] — 2026-11-22

### Fixed

- `serve`: uploads from a phone failed with "network error during the upload"
  on Wi-Fi and mobile data alike, while a desktop browser worked. The page cut
  every file with `file.slice()`, and a phone browser can fail to read a slice
  of a file picked from its gallery (on Android a `content://` document); XHR
  reports that only as a network error. A file of up to 32 MiB now goes as
  the File itself in one PUT, a larger one is read from start to end as a
  stream and sent in 32 MiB pieces from memory, a file the device cannot read
  says so, and a piece is retried twice after a network failure.

## [0.8.0] — 2026-11-21

### Added

- `map-anything serve`: the pipeline as a web service. A browser page uploads
  photos or one video (each file in 32 MiB raw PUT pieces appended on disk, so
  the body cap stays at 40 MiB; a name that cleans to one already in the job is
  refused rather than overwritten),
  queues the job with the CLI's options (max views, video fps, stride, pixel
  stride, confidence filter, attention window, sky mask), follows its progress,
  and opens the finished cloud in the ply viewer or downloads it as a PLY. Jobs
  live on disk under `~/.map-anything/jobs/<id>/` (or `--data DIR`) and survive a
  restart; one worker thread runs them one at a time, each as a child process of
  the same executable, so the server holds no GPU memory between jobs. The
  worker's claim, DELETE and start share one lock; SIGTERM ends the running
  child and queues its job again, and a start after a crash ends the orphaned
  child before rerunning the job. Optional HTTP Basic sign-in with `--password`
  or `$MAP_ANYTHING_PASSWORD`, and HTTPS with `--tls-cert`/`--tls-key` (the
  server warns when a password crosses a non-loopback address in plain text).
  `tests/serve_test.sh` covers the routes, the sign-in and the path checks
  without a GPU.
- Quality steps beyond the reference, all off by default in the CLI and on in
  the web service:
  - `--align N`: N sweeps of per-view Sim(3) alignment inside each window. The
    views agree to a few percent, so a wall comes out as two or three parallel
    copies; each view gets a correcting similarity fitted in closed form to
    pairs found by projecting its pixels into the other views (ICP with the
    cameras giving the correspondences), view 0 fixed and the metric scale
    renormalised every sweep. On the lego clip a cabinet wall's thickness
    falls from 43 to 27 mm (one window) and from 39 to 27 mm (72 views).
  - `--mv-check N`, `--mv-tol T`: keep a pixel only where N other views of the
    window see a surface at the same depth (default tolerance 3 %, inclusive; a
    window of fewer than N+1 views asks for all its others). Removes the
    floaters a single view believes in — sky behind foliage, a far "wall".
  - `--voxel M|auto`: fuse the cloud on a metric grid, one averaged point per
    cell; `auto` is two pixels' footprint at the median depth. Typically 2–5×
    fewer points, less noise, and a file a phone can open. Cells accumulate as
    points are emitted, keyed by full integer coordinates.
  - Pinhole intrinsics are fitted to each view's predicted rays
    (`gm_fit_pinhole`) for the projections these need.
- Requires ply 0.3.7: the viewer takes touch (orbit, pinch, two-finger pan).

## [0.7.5] — 2026-11-11

### Changed

- Requires onnx 0.13.0: a placeholder graph is `( onnx_empty_graph )` (Agora #526).

## [0.7.4] — 2026-10-21

### Fixed

- Requires gpukit 0.11.13 and onnx 0.12.4: the checkpoint upload from the mapped file
  and onnx's `rt_download` were refused as writes to an Arc's payload. Compiles again.

## [0.7.3] — 2026-10-21

### Fixed

- Installable as a dependency: the sources in `src/` imported their siblings as
  `src/<name>.nu`, which resolves only with the package root as the working
  directory, not under a consumer's `deps/map-anything/`. They are written relative to
  the importing file (`<name>.nu`) now, which resolves in both layouts.

## [0.7.2] — 2026-10-14

### Changed

- No `unsafe` code is left (1 in 0.7.1): the sky mask hands the onnx
  runtime its input as a byte view (onnx 0.12) and reads the score map as
  a checked `( Slice f32 )` of the download instead of peeking a raw
  pointer.

## [0.7.1] — 2026-10-14

### Changed

- Requires gpukit 0.11 (its kit state behind a lock; census accessors return a `String`).

## [0.7.0] — 2026-10-14

Requires NURL 0.73.0 and gpukit 0.10.3 (`gk_dbuf_upload_bytes`).

### Changed

- 1 `unsafe` function left (42 in 0.6.2): `sky_mask`, which hands the
  ONNX runtime its input by address. The geometry, the masks, the Sim(3)
  fit, im2col, the bicubic resampler and the preprocessing work on checked
  slices (`( Slice f )` / `( Slice u )` parameters in place of `*f` /
  `*u`); scratch buffers are typed Vecs instead of byte Vecs cast to
  pointers.
- The checkpoint (`Lw`) is its `St` plus a Locked list of failures: no
  Arc changed through a raw pointer. `lw_f32_bytes` (a checked view of a
  tensor's bytes) replaces `lw_f32_ptr`, and the weights upload from it
  with gpukit's `gk_dbuf_upload_bytes`. `lw_read` fills a slice;
  `lw_error` returns a `String` of its own; `pp_data` lends the frame's
  `( Vec f )`.
- The dense head's outputs download straight into the host buffers the
  geometry reads, one copy fewer per view.

### Verified

- geomcheck, sim3check, interpcheck and preproccheck give byte-identical
  output to 0.6.2 on deterministic inputs, ASan-clean, at the same speed.

## [0.6.2] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- Loops that read or wrote through `vec_data` pointers index slices (`slice_at` / `slice_put`, as fast as the pointers), and functions with nothing raw in them are no longer marked `unsafe`.
- 1 fewer functions are `unsafe` than in 0.6.1 (58 left).
- Requires safetensor 0.6 (`st_tensor_ptr` is `raw` there; the loaders that take tensor addresses were already `unsafe`).

## [0.6.1] — 2026-10-12

### Changed

- `tests/geomcheck.nu` reads its inputs into `Vec`s instead of raw
  allocations it never released; a missing or short file reads as an
  empty `Vec`.

## [0.6.0] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.5.2 does not compile under it.

### Changed

- `Lw` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of an
  `rcbox`. The share and drop hooks are ordinary safe functions — the Arc
  does the counting — and so are the constructors that build one from a
  whole value; every copy is still the same state, and its last owner
  releases it.
- 2 fewer functions are `unsafe` than in 0.5.2.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.
- Requires safetensor 0.5, onnx 0.11 and gpukit 0.10.
- The sky model's engine is a `?Engine` (F when it did not load), and the
  PLY writer is bound straight from `ply_create`.

### Removed

- `lw_none`: an `Lw` is always an open checkpoint, and the commands bind
  it straight from `lw_open`.

## [0.5.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.5.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. Bytes of a string are read through a bounds-checked
`Slice` of it (`slice_of_str`, `slice_byte`), where `nurl_str_at`
trusted the length its caller passed. No change in behaviour.

## [0.5.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.5.0 does
not compile under 0.71.0.

## [0.5.0] — 2026-10-03

Requires NURL 0.69.0, gpukit ^0.9, onnx ^0.9.1, safetensor ^0.4 and ply
^0.3. The command line is unchanged; the library API changed
incompatibly.

### Changed (API)

**Nothing is released by hand.**

- The checkpoint is an `Lw` handle instead of a `*Lw` pointer:
  `lw_open s → !*Lw String` → `lw_open s → !Lw String`, and every `lw_*`
  accessor takes `Lw` by value. Every copy is the same mapping and its last
  owner unmaps it; `lw_close` is now an optional early release (`sink Lw`)
  and `lw_none` is the empty slot.
- A fitted view is a plain `Frame` value: `pp_fit → !*Frame String` →
  `!Frame String`; `pp_width`/`pp_height`/`pp_data` take `Frame`; the views
  are a `( Vec Frame )` instead of frame pointers kept as words. `pp_free`
  is removed.
- Every function that took `* GpuKit` takes gpukit 0.9's `GpuKit` handle
  (`dn_load`, `dn_forward`, `dp_load`, `dp_forward`, `ph_load`,
  `ph_forward`, `sh_load`, `sh_forward`, `is_load`, `is_forward`,
  `ma_ws_new`, `ma_block_forward`, `maw_upload`, `maw_block`, …).
- The models' value structs (`Dino`, `MaBlk`, `MaWs`, `InfoShare`, `PoseH`,
  `ScaleH`, `Dpt`, `Sky`) hold buffers that release themselves, so
  `dn_free`, `ma_blk_free`, `ma_ws_free`, `is_free`, `ph_free`, `sh_free`,
  `dp_free` and `sky_free` are removed. Drop the calls. `Sky` holds onnx
  0.9.1's `Engine` handle instead of `*Engine`.

### Fixed

- The CLI's per-view host buffers were never freed; they are Vecs now and
  are released with the view. Every other host scratch block (geometry,
  edge mask, Sim(3) fit, sky mask) is a Vec too, so no early-return path
  can leak one.

## 0.4.7

Frame lists are compacted with `vec_replace` and trimmed with `vec_truncate` under NURL 0.67.0's element-dropping containers (#1143).

## 0.4.6

`--version` reported 0.4.4 while the manifest said 0.4.5.

The string is a literal in the source and nothing derives it from `nurl.toml`,
so the bump to 0.4.5 moved one and not the other. A published version cannot be
replaced, only superseded — which is what this is.

## 0.4.5

`dn_free`, `dp_free`, `is_free`, `ma_blk_free`, `ma_ws_free`, `ph_free` and 6 more now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.4.4 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

## 0.4.4

**Do not use 0.4.3.** It shipped the pin change below with a stale
`--version` literal — the binary announced `0.4.2`, a version whose
contents it does not have. A published version can be yanked but never
replaced, so the correction is this release: identical content, and
`--version` prints `0.4.4`.

## 0.4.3

Dependency requirements now pin the **major**, matching the rest of the
registry packages:

- `hub` `^0.1` → `^0`
- `gpukit` `^0.6.2` → `^0`
- `image` `^0.6` → `^0`
- `ply` `^0.2` → `^0`
- `video` `^0.1` → `^0`
- `safetensor` `^0.3` → `^0`
- `onnx` `^0.8` → `^0`

A minor release of a dependency is picked up on the next install now,
instead of stranding this package on the minor its requirement happened
to name. That was not hypothetical here: a registry install
resolved `gpukit` to a 0.6 series while the monorepo builds this package
against 0.7 — two different builds of the same commit.

No source change.

## 0.4.2

- Requires `http ^0` instead of `^0.3`. http has been 0.4.0 since #1014
  and 0.4.0 is what this package is built and tested against in the
  repo, but the manifest still asked for `^0.3` — so an install from the
  registry resolved http 0.3.2 and compiled against different code than
  anything here was tested on. `nurlpkg publish` refuses on exactly that
  mismatch, which is how it surfaced. The caret sits on the major so a
  0.x minor release of http cannot silently re-open the same gap in
  every consumer.
- `--version` reports the manifest version.

## 0.4.0

- Viewer: `--host`/`--addr` (bind address, default 127.0.0.1) and
  `--tls` (self-signed HTTPS) on both `map-anything view` and `--view`,
  riding on ply 0.2.0.

## 0.3.0

- **Long captures: windowed Sim(3)-stitched reconstruction.** Global
  attention is quadratic in the sequence, so past `--window` views
  (default 24) the run splits into overlapping windows, each
  reconstructed independently and stitched with a closed-form
  similarity: the `--overlap` views (default 6) exist pixel-for-pixel
  in both windows, so the correspondences are exact — Horn's quaternion
  method (4×4 Jacobi) recovers s, R, t to 7e-15 on synthetic transforms
  (tests/sim3check.nu). Window 0 sets the global metric frame; later
  windows' scale drift is absorbed by the stitch. Defaults unchanged:
  ≤ 24 views is still one batch, `--max-views 400` (or `--max-frames`,
  now an alias) actually works — 400 views of 518×294 in ~3 min on one
  RTX 4090 (~17 windows).


## 0.2.0

- **`--mask-sky`** — optional sky masking, the way the LingBot-Map demo
  does it: JianyuanWang's skyseg.onnx (U²-Net, fetched via hub on first
  use) scores sky per view through the onnx package on the GPU; the
  reference arithmetic (320×320, ImageNet norm, min–max → u8, bilinear
  back, keep at the map's minimum) is reproduced and agrees with the
  onnxruntime-driven reference on 99.97% of pixels. ANDs into the mask
  pipeline between the non-ambiguous and confidence masks.
- Rides on onnx 0.8.0 (dilated Conv, host-side INT64 shape folding,
  linear Resize, MaxPool ceil_mode — everything a torch U²-Net export
  needs) and gpukit 0.6.3 (`gkd_conv2d_dil`).


## 0.1.0

- **Initial release: MapAnything in pure NURL.** A port of Meta's
  [MapAnything](https://github.com/facebookresearch/map-anything)
  running the `facebook/map-anything-apache` checkpoint (1.23 B
  parameters, F32 safetensors): DINOv2-giant encoder (first 24 of the
  hub model's 40 blocks, SwiGLU, LayerScale), 16-block alternating
  global/frame attention over all views + a metric scale token, DPT
  head → unit ray directions + depth-along-ray + confidence + ambiguity
  mask, Reloc3r-style pose head (quat xyzw + translation), MLP scale
  head. `map-anything photos/` writes a metric world-space PLY;
  `--view` / `map-anything view` orbit it in the browser through the
  ply package's WebGL viewer.
- **Every stage verified against the reference PyTorch modules driven
  directly** (not re-implemented oracles): preprocessing byte-identical
  (aspect-mapped resolution table, Pillow-exact LANCZOS/bicubic, centre
  crop); pos-embed interpolation to print precision against
  `F.interpolate` (torch's plain a=−0.75 bicubic with DINOv2's +0.1
  scale-factor kludge); encoder within torch's own CPU-vs-CUDA f32
  spread (1.5e-3 max abs at |41|, mean 5e-7); info_sharing taps and
  final ≤ 2.4e-5; DPT ≤ 4.7e-5; pose head 4.5e-8; scale head exact;
  masks within the reference's own f32-vs-f64 noise. End to end on
  losslessly-decoded frames: median relative point error 2.5e-6,
  p99 1.2e-5. (On JPEG inputs the port's decoder differs from Pillow
  by ≤3 greylevels of IDCT rounding, which dominates: median 0.24%.)
- **Masking as the reference demo does it**: non-ambiguous mask
  (sigmoid > 0.5), optional `--conf-pct` percentile mask, and the
  MoGe-style edge mask (depth rtol 0.03 AND normals 5°) on by default;
  `--no-mask-edges` / `--no-mask` to relax.
- The reference flips TF32 on at import; all comparisons here run true
  f32 (TF32 off), worth 40× in max error.
- On one RTX 4090: 24 views of 518×294 in ~15 s, 51 views in ~26 s,
  end to end (weights load included).
