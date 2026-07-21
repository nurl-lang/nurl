# Changelog

## 0.1.0 (unreleased — M1 of the training-keystone arc)

Reverse-mode automatic differentiation over `tensor`: define-by-run
tape-recording ops, one reverse sweep, exact gradients for every registered
parameter.

- **The tape**: a flat single-owner arena (`{op, a, b, scalar}` nodes + two
  parallel tensor arrays). No graph objects, no per-node closures; reverse
  index order is topological order, and the sweep order is deterministic.
  `grad_param`/`grad_const` copy in, `gvar_value`/`grad_of` lend borrows out,
  `tape_free` releases everything; `tape_mark`/`tape_reset_to` give the
  minibatch pattern (params survive, intermediates drop, arena capacity kept).
- **M1 op set (CPU)**: add/sub/mul/div (equal shapes), neg/adds/muls,
  relu/sigmoid/tanh/exp/log/sqrt (forwards mirror tensor's `__umap` formulas
  bit-for-bit), sum/mean (all axes), mse composite. Constants report zero
  gradient. A shape mismatch poisons the tape — `tape_ok` goes false and
  `backward` refuses — instead of half-computing.
- **Verification**: every rule double-checked — central finite differences
  over composite graphs (fan-out included) and analytic identities exact to
  the bit (`d/dx Σx² == 2x` bitwise; a post-reset episode bitwise equal to
  the pre-reset one).

M2 (same release): the linear-algebra spine.

- Binary ops broadcast with full numpy rules (forward through the tensor
  package); backward sums each input's contribution over its broadcast axes
  (`_g_acc_reduce`, one documented row-major accumulation order).
- `g_matmul` / `g_bmm` (dA = g·Bᵀ, dB = Aᵀ·g, serial inner sums),
  `g_transpose`, `g_reshape`, `g_softmax(axis)` (dx = y⊙(g − Σ g⊙y)),
  `g_slice` (backward scatters into the source window), `g_concat` (backward
  splits at the axis).
- Verification: 9 new finite-difference cases (23 checks total) and a
  **PyTorch float64 oracle** — one graph through every op, rebuilt in torch
  from the exact same input bits: loss agrees to ~1e-16 relative, every
  parameter gradient to ~1e-13.

M3 (same release): optimizers + the training-loop proof.

- `src/opt.nu`: SGD and Adam over tape parameters, per-parameter L2
  (`opt_add` — the param-groups need in miniature), optional global-norm
  clipping. Adam's step count lives behind the `*Opt` heap pointer (the
  frozen-t bug class cannot recur) and shares the ecosystem's Adam
  arithmetic (runtime `1−β` forms, matching mlp and the aegpu kernels).
- A parameter whose gradient backward() never touched is skipped, not
  decayed (PyTorch's None-grad rule).
- Verification: the two-step Adam trajectory, the SGD+weight-decay update
  and the clipped step are each asserted BIT-EXACT against hand-computed
  references; end to end, the d-64-32-64-d autoencoder trained with the
  mark/reset minibatch loop reaches 5.7e-5 MSE from 0.319 on a noisy 2-D
  manifold in 6-D (60 epochs, 360 episodes, arena healthy throughout).

Next: M4 mlp 0.3.0 refactored onto grad; M5 GPU backward.
