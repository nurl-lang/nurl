# Changelog

## 0.2.0

- **Breaking:** `gk_open` now returns a heap `*GpuKit` (was a by-value
  `GpuKit`), so a kit can be held as a long-lived / lazily-probed singleton
  with a persistent kernel cache; `gk_close` frees it. All `gk_*` functions
  take `*GpuKit`. Update `: GpuKit kit ( gk_open 0 )` → `: *GpuKit kit ( gk_open 0 )`.
- Added `gk_compile` — warm the cache with a kernel and report whether it
  built, so a long-lived caller can detect a bad kernel at setup rather than
  on first launch.

Both shaken out by dogfooding gpukit on the `anomaly` package's GPU path.

## 0.1.0

- Initial release: `gk_open`/`gk_close`, typed bindings (`gk_in_f`/`gk_in_i`/
  `gk_out_f`/`gk_out_i`, raw `gk_buf_in`/`gk_buf_out`, `gk_i32`/`gk_i64`/
  `gk_f32`), the `gk_run` marshalling workhorse with a per-name kernel cache,
  and ready-made f64 kernels (elementwise, map, matmul, reduce-sum, dot).
