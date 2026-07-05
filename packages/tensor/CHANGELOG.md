# Changelog

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
