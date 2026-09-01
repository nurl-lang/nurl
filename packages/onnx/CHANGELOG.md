# Changelog

## 0.8.1

Dependency requirements now pin the **major**, matching the rest of the
registry packages:

- `tensor` `^0.4` → `^0`
- `gpukit` `^0.6` → `^0`
- `gpu` `^0.11` → `^0`

A minor release of a dependency is picked up on the next install now,
instead of stranding this package on the minor its requirement happened
to name. That was not hypothetical here: a registry install
resolved `gpukit` to a 0.6 series while the monorepo builds this package
against 0.7 — two different builds of the same commit.

No source change.

## 0.8.0

Everything a torch U²-Net export needs — proven on skyseg.onnx
(map-anything's --mask-sky), max 1.1e-6 against onnxruntime:

- **Host-side INT64 shape folding.** The Shape → Gather/Unsqueeze/
  Concat/Cast/Slice chains a torch export leaves behind now execute on
  the host (they are constants once the input shape is known); a
  host-int tensor lives in the ordinary value map under an RT_HOSTI
  sentinel. Device Gather/Concat/Slice are untouched — the host path
  only claims a node whose data is host-side.
- **Constant nodes.** The embedded TensorProto payload is parsed
  (INT64 values folded into the attribute's ints) instead of warping
  through "unsupported op".
- **Resize: `sizes` input + linear mode.** An explicit sizes input
  (opset ≥ 11, fed by the host chains) wins over float scales, and
  mode=linear runs half-pixel bilinear (pytorch_half_pixel agrees with
  half_pixel at every output size above 1). Nearest + scales behave as
  before.
- **Conv dilations** via gpukit 0.6.3's gkd_conv2d_dil — ignoring the
  attribute silently GREW every dilated map (pad 2, effective kernel
  read as 3) and the failure surfaced three stages later as Concat
  size mismatches.
- **MaxPool ceil_mode** rounds the output size up (U²-Net's 5→3).
- Concat's failure diagnostic now names the node, the input and both
  element counts.
- `gate_dump imgf` — run a model on a real f32 input from a file, for
  oracle comparisons.

## 0.7.3 and earlier

See git history (the package predates this changelog).
