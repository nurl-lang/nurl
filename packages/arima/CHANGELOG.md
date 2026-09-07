# Changelog

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
