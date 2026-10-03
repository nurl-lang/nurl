# Changelog

## [0.4.0] — 2026-10-03

Nothing is released by hand any more. Needs toolchain 0.69.0 and onnx 0.9.1
(`Engine` is a handle and `rt_download` returns a `GpuHost`).

### Changed (API)

- `img_to_nchw Image → *u` → `Image → ( Vec u )`: the NCHW f32 bytes are a
  Vec that releases itself; pass `( vec_data [u] t )` to the runtime.
- `detect_image * Engine e …` → `detect_image Engine e …` (onnx's `Engine`
  handle).
- `load_model s path * u pok → OGraph` → `load_model s path → ?OGraph`: a
  missing model is `F` instead of a flag poked into a caller-allocated cell.

The `objdet` CLI (stills and `--video`) and the wasm module's host interface
are unchanged.
