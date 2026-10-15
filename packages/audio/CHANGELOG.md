# Changelog

## [0.8.4] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- Loops that read or wrote through `vec_data` pointers index slices (`slice_at` / `slice_put`, as fast as the pointers), and functions with nothing raw in them are no longer marked `unsafe`.
- No `unsafe` left (29 before). `VadStream` keeps its state in a
  `Locked` (one thread may push while another takes) instead of an `Arc`
  changed through `arc_ptr`; the MP3 tables are filled through slices;
  the MDCT, side-info and Huffman passes index slices and windows. MP3
  output is bit-identical and encodes in the same wall time (6 s of
  stereo at 128 kbit/s: 111 ms best of 15 either way).

## [0.8.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.8.2 does not compile under it.

### Changed

- `VadStream` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of
  an `rcbox`. The share and drop hooks are ordinary safe functions — the
  Arc does the counting — and so are the constructors that build one from
  a whole value; every copy is still the same state, and its last owner
  releases it.
- One fewer function is `unsafe` than in 0.8.2.
- The MP3 encoder builds its state as one literal, and `mp3_encode` hands
  the finished stream out by moving it — no `mem_take`, so it is safe code
  again.

## [0.8.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.8.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.8.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.8.0 does
not compile under 0.71.0.

## [0.8.0] — 2026-10-03

**Nothing is released by hand.**

- `VadStream` is a handle instead of a `*VadStream` pointer:
  `vad_stream_new → VadStream`, and `vad_stream_push`, `vad_stream_poll`,
  `vad_stream_seg`, `vad_stream_take`, `vad_stream_flush` take the handle.
  Every copy is the same stream and the last owner releases it;
  `vad_stream_free` is an optional early release. Callers change
  `*VadStream` to `VadStream`.
- `stft_power` takes the stdlib's `FftPlan` handle (was `* FftPlan`), as
  `fft_plan` now returns it; the plan is released with its last owner
  instead of by `fft_free`.
- `mp3_free` is gone: the encoder's state is a plain value on
  `mp3_encode`'s stack, dropped when the encode returns, and the finished
  stream moves out. `mp3_encode` is unchanged.
- `Wav` is a plain value whose samples the compiler drops; `wav_free` is an
  optional early release (empty).
- Every `vec_free` / `string_free` / `args_free` in the library (mel,
  STFT/iSTFT, resampling, VAD, MP3) and the CLI is gone. Output is
  unchanged: the CLI's `mp3`, `resample` and `mel` output is byte-identical
  to 0.7.0's, and log-mel still matches numpy and Hugging Face's
  WhisperFeatureExtractor.

Requires NURL 0.69.0.
