# arima — seasonal ARIMA forecasting: exact, fast, streaming

A SARIMA(p, d, q)(P, D, Q)_s library for NURL, estimated the way R's
`arima()` and statsmodels' `ARIMA` estimate it, and built for a service
that keeps a model current point by point: fit once, absorb every new
observation in O(r²), forecast from where the data ended, refit on a
schedule. Pure NURL; the `gpu` package for fitting many series at once.

```
$ `arima/src/arima.nu`

: *ArimaModel m ( arima_fit y ( arima_spec_seasonal 0 1 1 0 1 1 12 ) )   // CSS-ML
: ArimaForecast fc ( arima_forecast m 12 )        // means and standard errors
: ArimaUpdate u ( arima_update m y_new )          // one Kalman step: innovation, variance, z
: Json report ( arima_coef m )                    // coefficients, σ², loglik, AIC, AICc, BIC, se
: String saved ( arima_to_json m )                // bit-exact, state included
: *ArimaModel best ( arima_auto y 12 )            // stepwise order selection by AICc
```

## What it computes

The model is

    φ(B) Φ(B^s) (1 − B)^d (1 − B^s)^D (y_t − μ) = θ(B) Θ(B^s) ε_t

with the seasonal factors multiplying the plain ones and the mean only
when nothing is differenced (a mean under a differenced series is a
drift, which is a regressor, not a mean).

**Estimation is CSS-ML.** Conditional sum of squares first — cheap, and
a good place to start — then exact Gaussian maximum likelihood over the
state-space form (Harvey's), started at the model's own stationary
covariance, so the likelihood is the true likelihood of the differenced
series, not an approximation that depends on how the series began. The
filter is run by the Chandrasekhar recursions (Morf, Sidhu & Kailath
1974): with a time-invariant model and a stationary start, the
covariance recursion's increment has rank one and its own O(r)
recursion, so a step costs O(r) where the Kalman form costs O(r²) — the
same innovations and variances, arrived at without the covariance. The
start needs only the first column of that covariance, solved in O(r²)
from the ARMA autocovariances. σ² is concentrated out. The optimizer is
BFGS with a backtracking line search over parameters transformed by the
Jones (1980) partial-autocorrelation map R uses, so every AR polynomial
it tries is stationary and every MA polynomial invertible. Standard
errors come from the numerical Hessian over the natural coefficients.

**Forecasting and streaming run on the full model.** After the fit, the
ARMA state is extended with the differencing (R's `makeARIMA`) and
filtered over the raw series with a diffuse start for the differencing
states. A forecast's mean and standard error come from that state; one
new observation is one filter step. `arima_update` absorbs it, reports
what the model had predicted, the innovation, its variance and the
z-score — how surprising the point was — and the next forecast starts
from there. A NaN observation is a gap: the state moves on and its
uncertainty grows, nothing is learned, the answer carries the prediction
and a NaN innovation. `arima_restart` puts the state back to where a
fresh fit's stands, so a stored history can be replayed through a model
whose state has moved past it; `arima_clone` copies a model, state and
all, so a copy can be stepped without moving the original. The model's
coefficients do not change; refit when the schedule says so. This is the
shape `packages/anomaly` wants: a model per feature, trained once, kept
current, judged on its innovations.

**Order selection** is the Hyndman–Khandakar stepwise search: how many
differences by the KPSS test (level stationarity, 5 %), a seasonal
difference when the autocorrelation at the seasonal lag exceeds 0.5,
then from four starting orders the best by AICc, each neighbour tried
in turn — one more or one fewer of p, q, P, Q, the mean toggled — until
nothing nearby is better (p, q ≤ 5; P, Q ≤ 2). Past 150 points or a
season longer than 12 the candidates are screened by conditional sum of
squares, as `auto.arima` approximates, and the winner refitted exactly.
One thing R does not do: every screened candidate conditions on the
largest order in play, so they are all scored on the same observations —
conditioning each on its own order lets the higher orders win on the
points they drop (measured on a true AR(1): AR(4) by 5 AICc, against the
exact likelihood's AR(1) by 4).

**Persistence** is JSON with every float as its IEEE bits, the filtered
state included, so a reloaded model streams on bit for bit.

## Verified against statsmodels

`tests/fixtures/statsmodels_cases.json` holds eight series and
statsmodels' exact-ML fits of them (`make_fixtures.py` regenerates it
with a Python that has statsmodels). `tests/arima_test.nu` fits each and
compares:

| case | order | coefficients | log-likelihood | forecast means, se |
|---|---|---|---|---|
| AR(1), MA(1), ARMA(2,1), ARMA(1,1)+mean | plain | within 2·10⁻⁵ | within 10⁻⁶ | within 10⁻⁵ |
| ARIMA(1,1,1) on a random walk | d = 1 | same | same | same |
| airline, log passengers | (0,1,1)(0,1,1)₁₂ | same | same | same |
| SAR(1)(1)₁₂ | seasonal AR | same | same | same |
| ARMA(2,1), n = 10 000 | plain | same | same | same |

The two implementations agree to the tolerance of their optimizers'
stopping rules, in every number a user reads. The oracle needs no
Python at test time.

## Speed

Measured on one core of an i7 (the CPU fit is single-threaded until a
likelihood is worth a thread; then the gradient's evaluations run on the
machine's cores):

| fit | n | arima | statsmodels |
|---|---|---|---|
| ARMA(2,1) | 10 000 | 11 ms | 460 ms |
| airline (0,1,1)(0,1,1)₁₂ | 144 | 5 ms | 450 ms |
| SARMA(1,0,1)(1,0,1)₂₄, hourly | 5 000 | 36 ms | — |
| SARMA(1,0,1)(1,0,1)₁₆₈, weekly | 3 000 | 0.34 s | — |

And the stepwise search, which evaluates thousands of likelihoods:

| `arima_auto` | n | arima |
|---|---|---|
| no season | 5 000 | 20 ms |
| season 24 | 2 000 | 0.5 s |
| season 24 | 5 000 | 1.0 s |
| season 144 | 2 000 | 3.1 s |

Three things make the filter fast: the Chandrasekhar step, O(r) instead
of the covariance form's O(r²) (a weekly season on hourly data has
r = 170; the search above went from 250 s to 3); the O(r²) start; and a
steady state — once the increment is below 10⁻¹⁴ the gain is fixed and
only the state moves. The CSS pass visits only the lags a seasonal
polynomial actually carries, bit for bit the dense recursion's sums.

**Many series at once.** `arima_fit_many series spec method` fits K
series under one specification together: every model's optimizer asks
for its round of likelihoods, the rounds are joined into one batch, and
the batch runs on the machine's threads — 64 series of 2 000 points in
58 ms where one after another takes 142. `arima_fit_many_gpu` sends the
same batch to a CUDA device (`src/arima_gpu.nu`), one thread per model
running the same recursions with the working vectors interleaved across
the models. With the step now O(r) the threads are the faster route at
every width measured (64 models: 0.47 s on an RTX 4090 against 58 ms on
twelve threads; 1 024 models: 8.2 s against 0.58 s — the rounds are
many, each small, and each re-uploads its inputs); the device path is
kept for its guarantee, and is where a wide-batch design would go. Whichever route, the numbers
are the same: the kernel runs the CPU's recursion in the CPU's order
with every operation rounded once (`__dadd_rn` and friends, never
fused), the transform and the start of the covariance stay on the host,
and the logarithms are summed on the host from the variances the device
returns. `tests/gpu_test.nu` pins it: the device's fits — coefficients,
σ², log-likelihood, standard errors, evaluation counts — equal the CPU's
bit for bit, on the `gpu` package's host C++ backend (`NURL_GPU=cpu`) and
on a CUDA device.

## Surface

```
( arima_spec p d q )                          → ArimaSpec
( arima_spec_seasonal p d q P D Q s )         → ArimaSpec   (mean on when d + D = 0)
( arima_spec_with_mean spec on )              → ArimaSpec
( arima_fit y spec )                          → *ArimaModel  CSS-ML
( arima_fit_method y spec ARIMA_CSS|ARIMA_ML ) → *ArimaModel
( arima_auto y s )                            → *ArimaModel  s = season, 0 = none
( arima_auto_d y s d D )                      → *ArimaModel  with the differences given
( arima_forecast m h )                        → ArimaForecast { mean se }   (arima_forecast_free)
( arima_update m y )                          → ArimaUpdate { predicted innovation variance z }   NaN y = a gap
( arima_restart m )                           the state back to a fresh fit's; replay with arima_update
( arima_clone m )                             → *ArimaModel  deep copy, state included
( arima_coef m )                              → Json
( arima_to_json m ) / ( arima_from_json s )   → String / ?*ArimaModel
( arima_phi m ) ( arima_theta m ) ( arima_sphi m ) ( arima_stheta m ) ( arima_mu m )
( arima_sigma2 m ) ( arima_loglik m ) ( arima_aic m ) ( arima_aicc m ) ( arima_n m ) ( arima_converged m )
( arima_fit_many series spec method )         → ( Vec *ArimaModel )   (arima_models_free)
( arima_fit_many_gpu series spec method )     → ( Vec *ArimaModel )   src/arima_gpu.nu
( arima_difference y d D s ) ( arima_kpss x ) ( arima_ndiffs y ) ( arima_nsdiffs y s d ) ( arima_acf x k )
( arima_free m )
```

`ArimaModel` fields a caller may read: `spec`, `sigma2`, `loglik`,
`aic`, `aicc`, `bic`, `n` (points absorbed), `n_fit`, `n_used`
(differenced points in the likelihood), `method`, `converged`,
`iterations`, `evals`, `se`, and after an update `last_innovation`,
`last_variance`, `last_predicted`.

## CLI

```
arima fit  FILE --order p,d,q [--seasonal P,D,Q,s] [--mean] [--css] [--horizon h]
arima auto FILE [--season s] [--horizon h]
```

FILE holds one number per line (a CSV's first column is taken; a header
that is not a number is skipped). The answer is `arima_coef`'s JSON
with, under `forecast`, the means and standard errors.

## Tests

`tests/arima_test.sh` runs `arima_test.nu` (87 checks: algebra — the
Chandrasekhar likelihood against the covariance filter's among them —
the oracle, streaming, JSON, the batch driver, order selection),
`gpu_test.nu` on both backends, and the CLI on the airline fixture — and
passes under AddressSanitizer / LeakSanitizer (`NURL_SAN=1`) with nothing
leaked. `tests/bench.nu` and `tests/bench_gpu.nu` time the shapes above.

## Design notes

- The optimizer is a state machine (`__ar_bfgs_requests` /
  `__ar_bfgs_absorb`): it says what it wants evaluated and takes the
  answers, and whoever drives it evaluates the requests in place, on
  threads, or on a device. That is what lets K fits share one batch and
  every route produce the same numbers.
- Late data and the streaming state: `arima_update` is the filter's
  own step, so the state after n updates equals the state of a filter
  run over the whole series at once — the test proves it through a JSON
  round trip.
- The CSS stage starts from zero coefficients (the mean at the sample
  mean); ML starts from CSS's answer. When CSS ends outside the
  stationary region the transform has no preimage, and ML starts from
  zero instead.
