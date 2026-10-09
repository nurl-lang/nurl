# Changelog

## [0.8.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.8.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

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
