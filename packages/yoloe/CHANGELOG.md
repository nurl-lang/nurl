# Changelog

## [0.8.3] — 2026-10-29

### Fixed

- The BPE tokenizer's encoder table keys the arena's copy of each key. It
  read the key through the parameter after handing it to the arena, which
  the compiler now rejects (agora #152). The table and the tokens are the
  same.

## [0.8.2] — 2026-10-21

### Fixed

- **`img_to_nchw_norm` did not compile** (and so neither did yoloe nor yoloe-demo): it filled a
  `GpuHost` through `gpu_host_f32`'s view, a write to the payload of the Arc the buffer's copies
  share. It fills the cells with `gpu_host_fill_f32`, before the buffer is a GpuHost; the values
  are the same.
- `nurl_peek_i32` / `nurl_peek_f32` are declared to read their base only (`in *u`).

## [0.8.1] — 2026-10-16

- The terminal preview reads the terminal's size with stdlib's `term_width` / `term_height` instead of its own `unsafe` ioctl on stdout. It also honours `$COLUMNS` / `$LINES` off a tty now. `unsafe` functions: 8 → 7; the rest are the X11 window and the V4L2 camera, which talk to their kernels' ABIs through the FFI.

## [0.8.0] — 2026-10-15

### Changed

- `Camera` and `XWin` are owned values (one holder, released by their
  drop) instead of shared handles changed through `arc_ptr`: `cam_close`
  and `xwin_close` take the value, `xwin_show` takes the window `inout`.
  The `unsafe` left is the V4L2 ioctl/mmap ring and the X11 calls.

## [0.7.8] — 2026-10-14

### Changed

- Requires onnx 0.12, whose run entry points take the input as a checked
  byte view and whose tensors own their device buffers. No change here.

## [0.7.7] — 2026-10-14

### Changed

- Requires gpukit 0.11 (its kit state behind a lock; census accessors return a `String`).

## [0.7.6] — 2026-10-14

### Changed

- 6 fewer `unsafe` functions (13 left, each an ioctl, an mmap'd V4L2
  buffer or an Xlib call): `cam_ok` / `cam_w` / `cam_h` / `xwin_ok` read
  their handle through `arc_get`, the terminal preview averages into a
  `( Vec i )` instead of poking a scratch buffer, and a V4L2 request buffer
  is zeroed through its Vec.

## [0.7.5] — 2026-10-14

Requires gpu 0.17 and onnx 0.11.2.

### Changed

- Decode, masks and image packing are safe code (34 → 24 `unsafe`; what
  is left is the V4L2 camera, the X11 window and the terminal size, all
  FFI). Model outputs are `GpuHost`s read through `Slice f32` views,
  `img_to_nchw_norm` returns a `GpuHost`, `mask_coeffs` / `mask_logits`
  return `Vec f` (each logit still rounded to f32), and the prompt
  tool and the forward tests run through `rt_run_host` /
  `rt_run_two_host` / `rt_run_tokens_host`. Every output is
  bit-identical; `mask_logits` sums a prototype plane at a time (the
  same order per pixel) and is 10–20% faster, image packing 15–30% faster
  (best-of-60 timings against the pointer code).

### Fixed

- A class list longer than the model's made `yolo_decode` and
  `mask_coeffs` read past the output, and the forward tests compared
  past a short output; they now decode nothing / report the mismatch.

## [0.7.4] — 2026-10-12

Requires NURL 0.73.0. No change of its own beyond its dependencies.

### Changed

- Requires gpu 0.16.

## [0.7.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.7.2 does not compile under it.

### Changed

- `Camera` and `XWin` keep their state in an `Arc` (stdlib/std/arc.nu)
  instead of an `rcbox`. The share and drop hooks are ordinary safe
  functions — the Arc does the counting — and so are the constructors that
  build one from a whole value; every copy is still the same state, and
  its last owner releases it.
- 4 fewer functions are `unsafe` than in 0.7.2.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.
- Requires onnx 0.11, gpu 0.15 and gpukit 0.10.

## [0.7.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.7.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. The BPE vocabulary builder hands `__enc_put` the
arena and the encoder table it changes instead of the whole tokenizer,
so a symbol read out of the byte encoder stays valid across the call, as
0.72.0's borrow rules require. Tokens are unchanged.

Loops that walked a string with `nurl_str_get` or decoded it with
`utf8_decode` — both measure the string from its start on every call, so
a scan is quadratic in the string's length, and nurlc 0.72 warns about
the shape — read through a view measured once (`slice_of_str` +
`slice_byte` / `utf8_decode_at`); the CLIP pre-tokenizer measures the
text once and hands the view to its helpers. No change in behaviour.

## [0.7.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.7.0 does
not compile under 0.71.0. The BPE tokenizer registers a merge rank
before the line moves into its arena.

## [0.7.0] — 2026-10-03

Nothing is released by hand any more. Needs toolchain 0.69.0 and onnx 0.9.1
(`Engine` is a handle and `rt_download` returns a `GpuHost`).

### Changed (API)

- `img_to_nchw_norm Image → *u` → `Image → ( Vec u )`: the NCHW f32 bytes are
  a Vec that releases itself; pass `( vec_data [u] t )` to the runtime.
- `mask_coeffs … → *u` and `mask_logits … → *u` → `( Vec u )` (same rule; the
  caller no longer frees them).
- `Camera` (`src/v4l2.nu`) is a handle: every copy is the same stream and its
  last owner stops it, unmaps the buffer ring and closes the fd.
  `cam_close` is now an optional early release.
- `XWin` (`src/window.nu`) is a handle: its last owner frees the XImage and
  the GC and closes the display. `xwin_close` is an optional early release;
  new `xwin_none w h` is the window that never opened. The pixel buffer is
  the window's own Vec.
- New `tokenizer_none` (`src/bpe.nu`): an empty tokenizer (sot = -1) for a
  field that holds one only when free-text prompting is on.
- The internal `__free_strvec` helper is gone; the BPE tokenizer releases
  nothing by hand.

The `yoloe detect|seg|cam` CLI is unchanged.

### Fixed

- Closing the X window used to close the display only, leaking the XImage
  and its pixel buffer; both are released now (and the GC is freed
  explicitly).
