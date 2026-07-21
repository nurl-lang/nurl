# Changelog

## 0.3.0

**New: `mlp_fit_grad` / `mlp_train_grad` — the same training recipe driven by
the `grad` autograd engine.** mlp is now the first consumer of the ecosystem's
reverse-mode autodiff package: instead of hand-derived layer deltas, the loss
is written once as a tape expression — `L = (Σ‖x̂−y‖² + α·Σ‖W‖²)/(2·B)` — and
`backward` produces exactly the gradient the hand path feeds Adam
(`(Σδa + αW)/B`). Everything else is shared with `mlp_fit`: same Glorot init
from the same seeded PRNG draws, same shuffles, same validation split, early
stopping, best-weight restore, and restart selection.

- The engines are recipe-equal, not bit-equal (batched matmuls accumulate in
  a different order than per-row loops) — in practice they land within ~14
  significant digits of each other on the oracle workload, flag the same
  outliers, and BOTH pass the sklearn oracle independently (`tests/oracle.sh`
  now runs each engine against the reference).
- The hand-written path is unchanged and remains the default — `mlp_fit` /
  `mlp_train` produce bit-identical results to 0.2.0, so the `anomaly`
  package's GPU-training parity guarantee is untouched.
- New dependency: `grad ^0.1` (which brings `tensor`). Only the `_grad`
  entry points touch it.

## 0.2.0

**Fixed: Adam's bias correction was frozen at t = 1.** `__mlp_adam` kept its
step counter as a scalar field on the `Mlp` struct — but NURL structs pass by
value (only their `Vec` fields alias), so `= . m t + . m t 1` incremented a
copy and the counter never advanced. Every minibatch after the first ran with
the t = 1 correction, i.e. a permanently inflated effective learning rate
(lr·√(1−β₂)/(1−β₁) ≈ 0.316·lr·√10 instead of the documented, sklearn-matching
schedule that decays toward lr).

- The step count now lives in `mlp_train` as a local and is passed to the
  Adam step explicitly; the vestigial `t` field is removed from `Mlp` (nothing
  outside the Adam step ever read it, and `mlp_save` never persisted it).
- **Trained networks change** versus 0.1.x for any multi-batch training run —
  that is the fix. The sklearn oracle still passes with 100 % outlier-flag
  agreement (and a tighter MSE ratio); persisted models load unchanged
  (`mlp_save`/`mlp_load` round-trip only sizes + weights).
- Found by the `anomaly` package's GPU-training parity work: a bit-exact GPU
  mirror of `mlp_train` disagreed with the CPU only from the second minibatch
  on, and the diff isolated the frozen counter.

## 0.1.0

Initial release — a trainable MLP in pure NURL, faithful to sklearn's
`MLPRegressor` recipe and proven against it as an oracle.

- Dense layers + ReLU (linear output), Glorot-uniform init from a seeded
  PRNG (bit-identical networks across platforms for a fixed seed).
- Minibatch Adam (bias-corrected), squared loss with L2, sklearn's
  batch-size "auto" (min(200, n)), per-epoch seeded shuffles.
- Early stopping on a held-out validation split with best-weight restore;
  the same patience applies to the training loss when disabled.
- `mlp_fit` deterministic restarts — a narrow ReLU bottleneck can die at
  init and collapse the net to predicting the mean (sklearn shares the
  failure mode and leaves the retry to the user; here it is a feature).
- JSON persistence with every f64 as its bit pattern: reload is exact.
- MinMax scaler (fit/apply/save/load, zero-range columns → 0).
- Tests: 23 offline checks (ASan + LSan clean) and a sklearn oracle run —
  same data and architecture, reconstruction at the same noise floor,
  100 % agreement on p95-rule outlier flags.
