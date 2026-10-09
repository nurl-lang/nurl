# Changelog

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
