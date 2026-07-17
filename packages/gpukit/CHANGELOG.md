# Changelog

## 0.4.0

Dev-layer op family — the kernel library a full CNN / transformer forward
pass needs, so tensor and onnx can share ONE set of device kernels
(tensor M5 / onnx M4b groundwork):

- **`GK_I64`** element type (`long long`) for index tensors, with exact
  `gk_dbuf_upload_i` / `gk_dbuf_download_i` host views (`Vec i`); the f64
  views convert by C truncation. The f64 upload/download paths now enforce
  their length contracts (short source pads through staging, short
  destination fails closed — no out-of-bounds host access in any case).
- **`gkd_ew_bc`** — elementwise binary with full N-D (≤6 dims) stride
  broadcast: output dims + per-input stride tables (stride 0 broadcasts a
  dim = numpy broadcasting). The wrapper proves the largest reachable
  offset fits inside each input before launching.
- **`gkd_bmm`** — batched matmul `Y[b,M,N] = A[b,M,K]·B[b,K,N]` with
  per-operand batch broadcast (a single matrix can serve every batch).
- **`gkd_gather` / `gkd_scatter`** — axis view (outer, ax, inner) with
  GK_I64 indices; negative indices wrap per ONNX, out-of-range reads give
  0 / writes are skipped (never out of bounds).
- **`src/devops.nu`** — the NN operator family, kernel bodies lifted from
  packages/onnx's proven f32 operator set and generalised over the element
  type with IDENTICAL arithmetic order (the GK_F32 instantiation is
  bit-compatible): `gkd_gemm` (alpha/beta/transB/optional bias),
  `gkd_conv2d`, `gkd_convtranspose2d`, `gkd_maxpool2d` (NCHW, batch 1),
  `gkd_batchnorm`, `gkd_leakyrelu`, `gkd_clip`, `gkd_erf`,
  `gkd_layernorm`, `gkd_softmax_ax` (interior axis), `gkd_copy_ax`,
  `gkd_slice_ax`, `gkd_perm` (N-D ≤6 transpose), `gkd_resize_nn`,
  `gkd_expandlast`, `gkd_reducel2`, `gkd_argmax` (any dtype → GK_I64),
  `gkd_eos_gather` (CLIP EOS read-out). Data-movement ops accept GK_I64;
  arithmetic ops are float-only.
- Every wrapper validates buffers, dtypes and sizes and fails closed —
  a wrong shape never reaches the device. `tests/opscheck.nu`: 57 checks
  (f32 + f64 + i64 + fail-closed guards) vs numpy on CUDA and the CPU
  backend, ASan clean.
- **`gk_autosync` / `gk_sync`** — gk_run_dev (and every gkd_* kernel)
  normally syncs the device after each launch; an executor chaining
  hundreds of launches (the onnx graph walk) can turn autosync off and
  sync once at the end. The CUDA stream serialises kernels and downloads
  synchronise implicitly, so results are unchanged.

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
