### Performance

- **hub downloads over many connections at once, and resumes by range**
  (Agora #523, packages/hub 0.3.0). Hugging Face's CDN holds one connection
  to a fraction of a megabyte a second, and hub fetched one file at a time
  over one. A file above 32 MiB is now cut into ranges that up to `--conns`
  connections (default 8) fetch at once with `Range: bytes=a-b`, each
  written into the staging file at its offset, and `hub dir` / `hub pull`
  fetch `--jobs` files side by side (default 2) under one progress line with
  the total rate. A finished range is flushed and recorded beside the
  staging file, so an interrupted pull fetches only the ranges it lacks; a
  dropped or stalled connection is retried from its first missing byte. The
  whole file is still hashed against Hugging Face's published sha256 — a
  corrupted range fails it and is discarded — and a second hub on the same
  file is refused while the first runs.
