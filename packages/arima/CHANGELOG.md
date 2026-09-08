# Changelog

## 0.2.0

- **The exact likelihood by the Chandrasekhar recursions.** With a
  time-invariant model started at its stationary covariance the covariance
  recursion's increment has rank one and its own recursion, so a filter
  step costs O(r) instead of the Kalman form's O(r²), and the start needs
  only the first column of the covariance, solved in O(r²) instead of r³.
  The innovations and their variances are the covariance filter's (pinned
  to 1e-9 relative in the algebra test; the statsmodels oracle unchanged).
  A weekly-season fit (r = 170, n = 3 000) went from 10 s to 0.34 s; the
  stepwise search on a daily season from 42 s to 0.5 s and on a weekly one
  from 250 s to 3 s. The device kernel runs the same recursion, one thread
  per model with the working vectors interleaved across the models, bit for
  bit the CPU's on both backends.
- **The stepwise search screens fairly.** Candidates are screened by
  conditional sum of squares past 150 points or a season longer than 12
  (R's `approximation` rule) and the winner is always refitted exactly. Every
  screened candidate now conditions on the largest order in play, so the
  candidates are scored on the same observations: conditioning each on its
  own order let the higher orders win on the points they drop — on a true
  AR(1), AR(4) won by 5 AICc where the exact likelihood prefers AR(1) by 4.
  A screened candidate no longer pays for standard errors or a filtered
  state it will not keep. The CSS pass visits only the lags a seasonal
  polynomial carries (bit-identical sums; 25× fewer terms for a season).
- **Streaming additions for a detector.** `arima_update` with a NaN
  observation is a gap: the time update alone, the answer carrying the
  prediction and a NaN innovation. `arima_restart` puts the state back to a
  fresh fit's so a stored history can be replayed; `arima_clone` deep-copies
  a model so a copy can be stepped without moving the original. Restart +
  replay reproduces the streamed state bit for bit (test).
- Shared job helpers renamed to single-underscore names (`_ar_job_new`,
  `_ar_jobs_run`, `_ar_jobs_free`), as the compiler's cross-file rule asks.

## 0.1.0

- **Seasonal ARIMA, exact and fast.** SARIMA(p,d,q)(P,D,Q)_s with an optional
  mean, estimated CSS-ML: conditional sum of squares, then exact Gaussian
  maximum likelihood by the Kalman filter over the state-space form with the
  model's own stationary covariance as the start — solved in closed form from
  the ARMA autocovariances — σ² concentrated out, BFGS over Jones-transformed
  parameters. Once the covariance recursion has converged a step costs O(r).
  Matches statsmodels' coefficients, log-likelihoods, forecasts and standard
  errors to 1e-5 on eight recorded fixtures; 10 000 points of ARMA(2,1) in
  16 ms where statsmodels takes 460.
- **Streaming.** Forecasts and updates run on the full state-space model
  (the differencing folded in, a diffuse start), so `arima_update` is one
  Kalman step that reports the prediction, the innovation, its variance and
  the z-score, and a reloaded model streams on bit for bit.
- **Order selection** by the Hyndman–Khandakar stepwise search (KPSS
  differences, seasonal-lag autocorrelation, AICc).
- **Many at once.** The optimizer is a request/absorb state machine; K fits
  share one batch of likelihoods per round, on the machine's threads
  (`arima_fit_many`) or on a CUDA device (`arima_fit_many_gpu`, one block per
  model) — bit-identical to one fit at a time, pinned by `tests/gpu_test.nu`
  on both the CPU backend and a device.
- A CLI (`arima fit|auto`), JSON persistence with the state, `tests/arima_test.sh`.
