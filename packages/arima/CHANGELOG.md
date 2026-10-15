# Changelog

## [0.6.2] — 2026-10-15

- No `unsafe` left. The device evaluator's two kernels are written in gpukit 0.11.5's checked subset: every access is an `LD` / `ST` of a buffer the call bound, and `arima_eval_gpu` is a plain function. The ML recursion now updates its state in place, with no copy-back loop, and reuses each new gain instead of reading it back. The arithmetic is unchanged and the results are bit-identical, so the checks cost nothing overall. On the CPU backend the device phase runs 10 % faster single-threaded (median 5.34 vs 5.94 s) and at parity with all threads (2.52 vs 2.53 s).

## [0.6.1] — 2026-10-14

### Changed

- Requires gpukit 0.11 (its kit state behind a lock; census accessors return a `String`).

## [0.6.0] — 2026-10-14

Requires NURL 0.73.0 with `stdlib/std/par.nu` (`par_map_index`).

### Changed

- No function is `unsafe` but the GPU evaluator, which launches this
  package's own kernel (101 were in 0.5.4). The Kalman filter, the
  likelihoods, the polynomial algebra and the BFGS machine index slices;
  a matrix row is a window of its own and a loop over `a[i+1]` reads a
  window that starts at 1, so the loop bound proves every index. The
  same fits are 23% fewer instructions than 0.5.4 (the ARMA filter 39%),
  with bit-identical estimates.
- The objective evaluations of a batch run through `par_map_index`
  (stdlib/std/par.nu): the jobs carry the series in an `Arc` and their
  own copy of the point, and the answers come back by index — the worker
  threads were handed raw addresses of the batch's slots. `ArimaCtx.w`
  is an `( Arc ( Vec f ) )`.
- An `ArimaModel` is a `Locked` handle (it was an `Arc` changed in place
  by `arima_update`, so two threads stepping one model raced); every
  call checks the state out and back in. `arima_se`, `arima_phi` and the
  other vector accessors return a copy rather than a view of the state.
- The BFGS state is a value the fit owns, the multi-series fit keeps its
  per-series state in a Vec it checks out by index, and the model is
  built as one value instead of field by field into zeroed memory.
- Requires gpu 0.17 (its handle structs are sealed and its address-taking functions `raw`); nothing here changed.

## [0.5.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.5.3 does not compile under it.

### Changed

- The evaluation jobs of a batch are values in a `Vec` the batch owns
  (each job reads the caller's series and point as views and writes its
  slot of the answers), the worker lanes are closures over the batch's
  address, and a prepare job's state-space form is a `Box` in its job.
  The fit's per-model contexts and optimizer states are `Box`es in the
  fit's tables, and the objective's parameter block is a `Box` too. All of
  it was raw memory allocated and released by hand; none of it is now.
- Requires gpu 0.16.

## [0.5.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.5.2 does not compile under it.

### Changed

- `ArimaModel` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of
  an `rcbox`. The share and drop hooks are ordinary safe functions — the
  Arc does the counting — and so are the constructors that build one from
  a whole value; every copy is still the same state, and its last owner
  releases it.
- One fewer function is `unsafe` than in 0.5.2.
- Requires gpu 0.15 and gpukit 0.10.

## [0.5.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.5.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.5.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.5.0 does
not compile under 0.71.0.

## [0.5.0] — 2026-10-03

**Nothing is released by hand.** `ArimaModel` is a handle over an rcbox
instead of a `*ArimaModel` pointer: the fits, `arima_auto*`, `arima_clone`,
`arima_from_json` (`?ArimaModel`) and `arima_fit_many*` (`( Vec ArimaModel )`)
return it, every copy is the same model, and the last owner releases it.
`arima_free`, `arima_forecast_free` and `arima_models_free` are optional
early releases. Callers change `*ArimaModel` to `ArimaModel`; code that read
fields directly uses the accessors, now with `arima_evals`, `arima_se`,
`arima_xk`, `arima_xcoef`, `arima_xt` and `arima_xtr` beside the existing
ones. The regressors' coefficients are copied into the model rather than
adopted. The GPU evaluator drives gpukit's self-releasing kit.

## 0.4.2

The fallback lane no longer frees its closure's environment by hand (NURL 0.67.0 closure ownership, #1141). Needs NURL 0.67.0: the job views it hands its workers rely on the compiler treating hand-managed stores as views (#1143).

## 0.4.1

`arima_forecast_free`, `arima_free`, `arima_models_free` and 6 more now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.4.0 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

## 0.4.0

- **A linear drift among the regressors.** `arima_fit_regress` /
  `arima_auto_regress` take a `trend` beside the Fourier periods: a series
  that climbs by a fixed amount a row is ARIMA(0,1,0) with drift exactly,
  and without the term the order search could only climb with a unit root
  that stops at the last level (a ramp forecast twenty steps ahead at a
  fraction of the naive error, test). The JSON carries it; the older
  `arima_fit_harmonic` / `arima_auto_harmonic` are the same without it.

## 0.3.0

- **Fourier terms for long and several seasons.** `arima_fit_harmonic` /
  `arima_auto_harmonic` fit K harmonics per period by least squares and the
  ARIMA on the residuals, and the terms ride with the model: `arima_update`
  subtracts the row's seasonal before the filter, `arima_forecast` adds it
  back, the JSON carries the terms and the regressors' clock, and
  `arima_restart_at` sets that clock for a replay that begins elsewhere
  than the fit did. Any period length (the day at a minute's step is
  1 440 rows, which a seasonal polynomial cannot carry as a state), several
  at once (the day and the week), O(K) a row. Test: both periods recovered
  from 11 000 points in well under a second; a thousand steps ahead the
  error is a fraction of the naive forecast's; restart-and-replay is
  bit-exact.

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
