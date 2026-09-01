# Changelog

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
