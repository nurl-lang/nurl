# Changelog

## [0.4.5] — 2026-10-14

### Changed

- Requires onnx 0.12, whose run entry points take the input as a checked
  byte view and whose tensors own their device buffers. No change here.
- Declares its `gpu` dependency (`^0.17.6`): `detect.nu` and `image.nu`
  import the gpu package directly since 0.4.4, which the manifest did not
  say, so a registry install had no `deps/gpu` to compile against.

## [0.4.4] — 2026-10-14

Requires gpu 0.17 and onnx 0.11.2.

### Changed

- No `unsafe` outside the wasm module's host-import wrappers (7 → 4):
  the NCHW input is a `GpuHost` built through a `Slice f32` view and run
  with `rt_run_host`, and the grid is decoded through a view of the
  download.

### Fixed

- `yolo_decode` read 21,125 floats from whatever buffer it was handed;
  a model with another output size read past it. It now decodes nothing
  from a grid of the wrong size.

## [0.4.3] — 2026-10-11

Requires onnx 0.11, whose `rt_none` is gone (an `Engine` is always an
engine), and so NURL 0.73.0. Nothing in objdet changed.

## [0.4.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.4.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

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
