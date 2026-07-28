# Changelog

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
