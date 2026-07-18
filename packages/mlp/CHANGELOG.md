# Changelog

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
