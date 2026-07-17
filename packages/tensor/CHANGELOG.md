# Changelog

## 0.4.0

M5 — the device layer grows to full ndarray coverage (over gpukit 0.4.0's
dev-layer op family; one broadcast implementation shared with the host
tensors — `_t_bshape` / `_t_eff_strides` / `_t_batch_eff` are now the
package-shared helpers):

- **Broadcast elementwise:** `dtensor_add/sub/mul/div` now broadcast with
  full numpy rules (≤6 dims). Same-shape pairs keep the plain kernel;
  everything else runs the stride-broadcast kernel (stride 0 = broadcast
  dim) in ONE launch — no materialised expansion.
- **`dtensor_bmm`** — batched matmul `[..,M,K]·[..,K,N] → [..,M,N]` with
  numpy batch broadcast. Uniform batches (both operands carry the batch,
  or one is a single matrix) run as one kernel launch; a general broadcast
  falls back to a per-batch matmul over device-pointer views — the same
  sequential-K kernel math either way.
- **`dtensor_gather` / `dtensor_scatter`** — along an axis with a host
  index vector: negative indices wrap (numpy/ONNX), out-of-range indices
  are REJECTED before anything touches the device; scatter returns a fresh
  tensor (duplicate-index write order unspecified, per ONNX).
- **`dtensor_conv2d` / `dtensor_conv2d_b` / `dtensor_maxpool2d`** — NCHW
  without the batch dim ([C,H,W]), symmetric zero padding, strides;
  `OH = (H + 2·ph − kh)/sh + 1`.
- Every entry point validates dtypes/shapes/axes and fails closed.
- Tests: 33 device checks vs numpy (f32 true-float32 + f64 + fail-closed
  guards) on CUDA; f64 rows bit-identical between the CUDA and CPU
  backends; ASan clean.

## 0.3.0

M3 — device-resident tensors (`src/dev.nu`).

- **`DTensor`** — a tensor whose data lives in GPU memory (a gpukit
  `GkBuf`): ops chain on the device with **no host roundtrips** — what a NN
  forward pass needs (upload weights once, stream activations through).
  Residency is explicit: `tensor_to_device kit t` / `dtensor_to_host kit d`;
  nothing syncs behind your back. `dtensor_free`, `dtensor_ok`,
  shape/size/dtype queries.
- Device ops (all `→ ?DTensor`): `dtensor_add/sub/mul/div` (same shape),
  `dtensor_adds/subs/muls/divs` (scalar), `dtensor_relu/sigmoid/exp/tanh/
  sqrt/log`, `dtensor_matmul` (2-D), `dtensor_softmax` (last axis, stable),
  `dtensor_sum → ?f`.
- **Numerics:** a TE_F32 DTensor computes IN float32 on the device
  (accumulation included) — true float32 semantics matching numpy float32 /
  onnxruntime. The HOST TE_F32 Tensor keeps its f64-compute + grid-rounding
  behaviour; elementwise results agree exactly, accumulations differ as
  documented. TE_F64 device ops are bit-compatible with host ops where the
  kernel accumulates sequentially.
- Verified on CUDA (RTX 4090) and the CPU backend: chained
  matmul→scale→tanh→softmax pipeline + a 128×64·64×96 float32-accumulation
  matmul — **12/12 vs numpy per dtype, ASan-clean**. Skips cleanly with no
  backend.

## 0.2.0

M2 — batched matmul, softmax, slicing, concat, argmax/argmin.

- `tensor_bmm a b` → `?Tensor` — N-D batched matmul. The last two dims are the
  matrix `(…,M,K)·(…,K,N)`; leading batch dims broadcast by the numpy rule.
- `tensor_softmax t axis` → `Tensor` — numerically stable softmax over one axis
  (subtracts the axis max before exp).
- `tensor_slice t starts stops` → `?Tensor` — per-dimension half-open slice
  `[start, stop)`; one `start`/`stop` entry per dim.
- `tensor_concat2 a b axis` → `?Tensor` — concatenate two tensors along an axis
  (all other dims must match).
- `tensor_argmax t axis keepdim` / `tensor_argmin t axis keepdim` → `Tensor` —
  index of the max/min along an axis (indices as f64; `keepdim` is a `b`).

Verified against numpy (incl. batch broadcasting): **25 / 25, ASan-clean.**

## 0.1.0

Initial release. The reusable ndarray layer: `Tensor` (row-major, f64 compute,
F32-grid dtype), creation (`arange`/`zeros`/`ones`/`full`/`from_data`), reshape /
transpose / permute, numpy-broadcasting elementwise + scalar ops, unary maps
(exp/log/sqrt/relu/sigmoid/tanh…), 2-D matmul (GPU via gpukit for large
problems), and axis/global reductions. Verified against numpy — 17 / 17,
ASan-clean.
