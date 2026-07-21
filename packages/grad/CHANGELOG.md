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

Next: M2 broadcasting + matmul/bmm/softmax backward with a PyTorch oracle;
M3 SGD/Adam; M4 mlp 0.3.0 refactored onto grad; M5 GPU backward.
