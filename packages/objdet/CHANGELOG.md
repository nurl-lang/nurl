# Changelog

## [0.4.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.4.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

## [0.4.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.4.0 does
not compile under 0.71.0.

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
