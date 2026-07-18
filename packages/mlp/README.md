# mlp — a trainable multi-layer perceptron, pure NURL

Dense layers, ReLU, minibatch **Adam**, **early stopping** — the ecosystem's
first *trainable* neural-network package (everything else runs inference).
The recipe is deliberately faithful to sklearn's `MLPRegressor`, and the
test suite proves it against that oracle: on the same data, the same
architecture reconstructs equally well and flags the same outliers.

```nurl
$ `src/mlp.nu`

: ( Vec i ) sizes ( vec_new [i] )      // 6 → 64 → 32 → 64 → 6
( vec_push [i] sizes 6 ) ( vec_push [i] sizes 64 ) ( vec_push [i] sizes 32 )
( vec_push [i] sizes 64 ) ( vec_push [i] sizes 6 )

: ~ MlpCfg cfg ( mlp_cfg_default )     // adam lr 0.001, early stopping, seed 42
: MlpFit fit ( mlp_fit sizes X n 6 X 6 cfg 3 )   // ← an AUTOENCODER: target = input
: Mlp ae . fit model

: ( Vec f ) recon ( mlp_predict ae x ) // reconstruction of one row
: String js ( mlp_save ae )            // JSON, every f64 bit-exact
```

## What it does

- **`mlp_new sizes seed`** — Glorot-uniform init from a seeded PRNG: a fixed
  seed gives the identical network on every platform.
- **`mlp_train m X n d Y dout cfg`** — minibatch Adam (β₁ 0.9, β₂ 0.999,
  bias-corrected), squared loss with L2 (`alpha`), `batch` 0 = min(200, n)
  (sklearn's "auto"), per-epoch seeded shuffles. With `early_stop` a
  `val_frac` split is held out once; training stops after `n_no_change`
  epochs without the validation MSE improving by more than `tol`, and the
  **best** weights seen are restored — not the last.
- **`mlp_fit sizes X n d Y dout cfg restarts`** — train `restarts` networks
  (seeds `seed`, `seed+1`, …) and keep the best by the plateau criterion.
  This exists because a narrow ReLU bottleneck can die at init (every
  pre-activation negative → the net collapses to predicting the mean);
  sklearn has the same failure mode and leaves the retry to the user.
  Here it is a deterministic feature.
- **`mlp_predict` / `mlp_mse`** — inference and evaluation.
- **`mlp_save` / `mlp_load`** — JSON persistence with every weight stored
  as its f64 **bit pattern**: reload is bit-exact (decimal text would
  silently perturb a trained model).
- **`minmax_fit` / `minmax_apply` / `minmax_save` / `minmax_load`** — the
  MinMax scaler the autoencoder recipe wants (zero-range columns → 0).

## An autoencoder for anomaly detection

Train with the input as the target, threshold the reconstruction error at
the 95th percentile of the training errors, and a point whose
per-row MSE exceeds the threshold is anomalous:

```nurl
: MlpFit fit ( mlp_fit sizes X n d X d cfg 3 )
// per-row MSE over the TRAINING data → sort → p95 threshold
// score a new point: mse(mlp_predict(x), x) > threshold ⇒ anomaly
```

The [`anomaly`](../anomaly) service wraps exactly this (with an
Isolation-Forest pre-filter that removes anomalies from the training data
first), but the building block is here, reusable.

## Verified

- `tests/mlp_test.nu` — 23 checks: shapes, seeded determinism, the Glorot
  bound, XOR fit, bit-exact save/load, AE manifold reconstruction,
  off-manifold discrimination, dead-bottleneck collapse + restart rescue,
  MinMax edge cases. ASan + LeakSanitizer clean.
- `tests/oracle.sh` — the sklearn oracle: same data, same (64, 32, 64)
  architecture; reconstruction MSE within a small constant of
  `MLPRegressor`'s (both at the injected-noise floor) and **100 %**
  agreement on which injected outliers the p95 rule flags.

## Scope

f64, CPU, tabular-scale data (the anomaly service's rings are thousands of
points × tens of features — fractions of a second per epoch). No
convolutions, no attention, no autograd graph: three dense layers and the
truth. For GPU-scale tensors see `gpukit` / `tensor`.
