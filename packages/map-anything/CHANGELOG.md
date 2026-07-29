# Changelog

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
