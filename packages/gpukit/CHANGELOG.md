# Changelog

## 0.3.1

- Manifest only: the gpu dependency range is `^0.3` (0.3.0 was published
  with `^0.2`, which is disjoint from onnx 0.5.0's `^0.3` — a resolver
  could try to install two gpu versions side by side).

## 0.3.0

Device-resident layer (`src/dev.nu`) — data stays on the GPU between ops:

- **`GkBuf`** — an element-typed device allocation (`GK_F32` | `GK_F64`)
  with `gk_dbuf_new` / `_free` / `_upload` / `_download` (f64 host vectors
  convert to/from the buffer's element type through a staging buffer).
- **`gk_run_dev`** — compile-cached launch + sync over RAW device args
  (`gk_arg_dev` + `gpu_arg_*` scalars), zero marshalling.
- **`gkd_*` kernels**, dtype-generic (float/double sources cached per
  dtype): elementwise `add/sub/mul/div` with 1-element scalar broadcast,
  unary `relu/sigmoid/exp/tanh/sqrt/log`, `matmul` (sequential-k
  accumulate), numerically-stable row `softmax`, `sum` reduction.
- **Numerics:** GK_F32 computes IN float32, accumulation included — true
  float32 semantics matching numpy float32 / onnxruntime. GK_F64 matches
  kernels.nu exactly. `tests/devcheck.nu`: 12/12 vs numpy on CUDA.

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
