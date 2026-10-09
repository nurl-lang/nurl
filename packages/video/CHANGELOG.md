# Changelog

## [0.2.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.2.1 does not compile under 0.72.0. Bytes of a string are
read through a bounds-checked `Slice` of it (`slice_of_str`,
`slice_byte`), where `nurl_str_at` trusted the length its caller passed.
No change in behaviour.

## [0.2.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.2.0 does
not compile under 0.71.0.

## [0.2.0] — 2026-10-03

Nothing is released by hand any more.

- `VidAvi` is a handle over the opened AVI instead of a struct the caller
  had to `vid_avi_close`: every copy is the same open file, and the last
  owner closes it, as `vid_avi_close` did (which stays as an optional early
  release). `vid_avi_open` builds the handle first, so its error paths
  close the file by letting go of it. The stream metadata is read through
  `vid_avi_fps_num`, `vid_avi_fps_den`, `vid_avi_vstream`,
  `vid_avi_movi_off` and `vid_avi_movi_end` instead of struct fields.
- Every `string_free` / `vec_free` / `output_free` in the library and the
  CLI is gone; the compiler drops them.

## 0.1.0 — 2026-07-28

Extracted from `lingbot-map` 0.7.0, where it was `src/video.nu`; the
history of the code before this point is that package's.

- MJPEG-AVI frame extraction in pure NURL: RIFF walk for fps / stream /
  movi, `NNdc` chunks written as numbered JPEGs.
- ffmpeg fallback for every other container, with an actionable error
  when ffmpeg is absent.
- fps sampling (`round(src_fps/target)`, floor 1); re-extraction removes
  exactly the frames a previous run wrote before writing its own.
- CLI: `video frames <file> [--fps n] [--out dir] [--quiet]`,
  `video probe <file.avi>`, and `video <file.avi>` as shorthand.
