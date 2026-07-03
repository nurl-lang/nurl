# `anomaly` — streaming anomaly-detection service (specification)

Status: **draft / not yet implemented.** This document specifies the package;
it does not describe existing code.

## 1. Motivation

The `iforest` package already ships the *core algorithm* — an Isolation Forest
that turns a numeric matrix into per-row anomaly scores. That is the kernel, but
it is not a usable anomaly-detection **service**: it has no notion of feature
preprocessing, no persistent models, no streaming ingestion, no thresholding,
and no way to ask "is *this single reading* anomalous, given everything I've
seen so far?".

This package fills that gap. It is a NURL re-implementation of the anomaly
detection interface currently provided by the Python service in
`~/dev/python-scripts-runner` (`model_training.py` + the Flask routes in
`api.py`). That service exposes a small, well-defined contract:

- named **dynamic models** that are *created on first use* and *train
  themselves* once enough data has been collected;
- **streaming ingestion** — you POST one data point at a time (sensor readings,
  metrics, log-derived features) and get back an immediate verdict;
- **heterogeneous features** — numeric, categorical (one-hot), and timestamp
  columns are accepted and encoded automatically;
- **multiple time-window versions** of each model (short-term, daily, weekly,
  …) so the same stream is judged against several horizons at once;
- **tunable thresholds** (contamination / decision margin) and a fine-tuning
  pass that re-calibrates them against observed data;
- **persistence** so a model survives a restart.

`anomaly` provides the same contract from pure NURL: a reusable **library**, an
installable **CLI**, and an optional **HTTP/JSON service** whose routes mirror
the Python API so existing clients keep working.

`anomaly` **depends on** and reuses `iforest` for the forest itself. It adds
everything *around* the forest.

## 2. Scope and non-goals

### In scope

- Feature preprocessing: numeric passthrough, categorical → deterministic
  one-hot, ISO-8601 timestamp → cyclical/calendar features.
- Per-feature **standardisation** (zero-mean / unit-variance), the NURL analogue
  of scikit-learn's `StandardScaler`, persisted with the model.
- **Model metadata**: column types, discovered categories, ordered feature
  names, scaler parameters, training schedule, per-version config.
- **Dynamic / streaming models**: create-on-first-use, a bounded in-memory (and
  persisted) ring of recent points, and schedule-driven retraining.
- **Multi-version models**: several time-windowed Isolation Forests per model,
  aggregated into one verdict.
- **Thresholding**: contamination and per-version `decision_margin`; the
  `fine-tune` re-calibration pass.
- **Persistence**: a documented on-disk layout (JSON metadata + a compact binary
  forest blob), pluggable so a second backend can be added later.
- **CLI** and **HTTP/JSON service** surfaces.

### Out of scope (for this package)

- ARIMA / multivariate *forecasting* endpoints (`/predict/arima`,
  `/predict/multivariate`) — those are time-series prediction, not anomaly
  detection, and belong elsewhere.
- GPU acceleration. The forest is CPU-only here; a later milestone may route
  training through the `gpu` package, but it is not required for correctness.
- Redis storage backend. The storage layer is designed to be pluggable, but only
  the file backend is specified as mandatory.
- Authentication / TLS termination — the HTTP layer is expected to sit behind
  the existing `swarm-mcp` / `net` machinery if exposed publicly.

## 3. Reference: the Python interface being ported

For traceability, this is the surface `anomaly` is modelled on. Endpoints marked
† are ported; the rest are explicitly out of scope (§2).

| Python route | Meaning | Ported |
| --- | --- | --- |
| `POST /detect/<model>` | ingest one point into a dynamic model, train if ready, return verdict | † |
| `POST /detect_only/<model>` | score one point, **never** ingest or retrain | † |
| `POST /force_train/<model>` | force an immediate retrain | † |
| `POST /detect_anomalies` | batch-score every row of a CSV file with a model | † |
| `GET  /models/dynamic` | list dynamic models | † |
| `GET  /models/dynamic/<model>/metadata` | model metadata | † |
| `GET  /models/dynamic/<model>/data` | recent data points | † |
| `POST /models/dynamic/<model>/reset` | drop data + models, keep name | † |
| `DELETE /delete_model/<model>` | delete a model entirely | † |
| `PUT  /api/dynamic/<model>/schedule` | change retraining schedule | † |
| `POST /api/dynamic/<model>/finetune` | re-calibrate decision margins | † |
| `POST /train/autoencoder/<model>` | train the autoencoder version | † (M6, optional) |
| `GET/POST /predict/arima/<model>` | ARIMA forecast | ✗ out of scope |
| `GET/POST /predict/multivariate/<model>` | multivariate forecast | ✗ out of scope |

Key defaults observed in the reference implementation (carried over verbatim):

- `MIN_DATA_POINTS = 50` — no detection before this many points; everything is
  "normal / warming up".
- `MAX_DATA_POINTS = 150000` — ring capacity per model.
- Retraining schedule: every `50` points below capacity, every `1000` points at
  capacity.
- Default model versions and their configs (`short_term` 180 min, `daily`
  1440 min, `weekly` 10080 min, `seasonal` 90 days, `timevector` window 100),
  each with `contamination = auto`, its own `decision_margin`, `n_estimators`,
  `max_samples = 256`, `random_state = 42`.
- Isolation Forest verdict convention: `predict == -1` ⇒ anomaly; `score` is the
  signed `decision_function` value (below the margin ⇒ anomaly).

## 4. Data model

### 4.1 Feature encoding

`preprocess_point(raw, meta) → (features, meta')` turns a record of named raw
values into an ordered numeric feature vector, updating metadata as new columns
or categories appear.

- **numeric** — parsed as `f`; parse failure is a hard error.
- **categorical** — value stringified; the column's category list is kept
  **sorted** so ordering is deterministic; emitted as one-hot features named
  `col_<category>`. New categories extend the vector (see §4.3 stability rule).
- **timestamp** — ISO-8601 parsed via `std/time`; expands to
  `col_hour`, `col_day`, `col_month`, `col_weekday` (float). (Cyclical
  sin/cos encoding is a candidate refinement, tracked as an open question.)
- Column type may be pinned in metadata (`numeric` / `categorical` /
  `timestamp`) or `auto`-detected on first sight and then frozen.

### 4.2 Standardisation

A `Scaler` holds per-feature `mean` and `inv_std` (`( Vec f )` each). Fit over
the training matrix; applied to every point before it reaches the forest and
persisted in metadata. Zero-variance features get `inv_std = 1` (i.e. pass
through) to avoid division blow-ups.

### 4.3 Metadata

Persisted as JSON (`std/ext/json`). Fields:

```
{
  "name":            string,
  "created":         iso8601,
  "column_types":    { col: "numeric"|"categorical"|"timestamp" },
  "categories":      { col: [sorted strings] },
  "feature_names":   [ordered feature names],   // authoritative feature order
  "scaler":          { "mean": [...], "std": [...] },
  "schedule":        { "below_max": 50, "at_max": 1000 },
  "versions":        { version_name: <version config>, ... },
  "n_points_seen":   int,
  "last_trained_at": int   // point count at last train
}
```

**Feature-order stability rule.** `feature_names` is authoritative once a model
is first trained. At scoring time a point is projected onto exactly that vector:
missing features default to `0`, unknown extras are dropped. This mirrors the
reference (`model_features` in metadata) and is what keeps categorical one-hot
encodings aligned across retrains.

### 4.4 On-disk layout (file backend)

```
<model_dir>/<name>/
  metadata.json            # §4.3
  data.bin                 # ring of recent points, row-major f + timestamps
  version_<v>.forest       # one compact forest blob per enabled version
```

The forest blob is a straight serialisation of the `iforest` node arena (§the
arena is already flat, so this is a length-prefixed dump of the SoA arrays plus
the per-tree root indices). The storage API is an interface (`store_*` fns) so a
non-file backend can be dropped in without touching callers.

## 5. Library API surface (`src/anomaly.nu`)

Signatures are indicative and follow the `iforest` house style (prefix calls,
caller-owned handles, `( Vec f )` row-major matrices).

### 5.1 Preprocessing & scaling

| Function | Result |
| --- | --- |
| `( anomaly_preprocess raw meta )` | `( Features , Meta )` — encode one record |
| `( scaler_fit data n_rows n_cols )` | `Scaler` |
| `( scaler_apply scaler point )` | `( Vec f )` standardised in place |
| `( scaler_free scaler )` | `v` |

### 5.2 Model lifecycle (dynamic / streaming)

| Function | Result |
| --- | --- |
| `( model_open store name )` | `Model` — create-on-first-use, load if present |
| `( model_ingest model raw )` | `Verdict` — add point, retrain if scheduled, then score |
| `( model_detect_only model raw )` | `Verdict` — score without ingesting/retraining |
| `( model_force_train model )` | `i` — retrain now, return points used |
| `( model_reset model )` | `v` — drop data + forests, keep name/schedule |
| `( model_delete store name )` | `v` — remove everything |
| `( model_finetune model )` | `FineTuneReport` — recalibrate margins |
| `( model_set_schedule model below_max at_max )` | `v` |
| `( model_metadata model )` | `Meta` |
| `( model_free model )` | `v` |

### 5.3 Batch (stateless) scoring

| Function | Result |
| --- | --- |
| `( anomaly_score_csv path opts )` | `BatchReport` — score every CSV row |

### 5.4 The `Verdict`

```
Verdict {
  ready:      i1      // false while warming up (< MIN_DATA_POINTS)
  anomaly:    i1      // aggregate decision across enabled versions
  score:      f       // aggregate (max-severity) score
  versions:   Vec VersionVerdict   // per-version { name, anomaly, score, margin }
}
```

Aggregation: a point is anomalous if **any** enabled version flags it; the
reported `score` is the most-severe version's score. (The reference checks all
versions and surfaces each; §6 preserves that in the JSON.)

## 6. HTTP/JSON service surface (`src/service.nu`, optional milestone)

The routes mirror §3 (ported column). Request/response shapes match the Python
service so existing dashboards and the `modelmanager` UI keep working:

- `POST /detect/<model>` body = `{ col: value, ... }` (numeric/categorical/
  timestamp), optional `timestamp`. Response = `Verdict` as JSON with the
  `versions` map, `status`, `model`, echoed `data_point`.
- `POST /detect_only/<model>` — same body, `Verdict`, no state change.
- `POST /detect_anomalies` body = `{ file_path, model_name? }` → batch report:
  `anomaly_count`, `anomaly_percentage`, `anomaly_indices`, `has_anomalies`,
  `anomaly_details` (first 100).
- model-name validation: `^[a-zA-Z0-9_]+$` (reject otherwise, mirrors reference).

The service is thin: parse JSON → call the library → serialise. It is
factored so it can be hosted directly (`std/net`) or registered as tools on the
existing `swarm-mcp` node.

## 7. CLI surface (`src/main.nu` → `anomaly`)

```
anomaly detect  <model> [--store DIR] key=val ...      # ingest + verdict
anomaly score   <model> [--store DIR] key=val ...      # detect-only
anomaly batch   [-f FILE] [-H] [--model M]             # score a CSV, like iforest but with a saved model
anomaly train   <model> [--store DIR]                  # force retrain
anomaly reset   <model> [--store DIR]
anomaly rm      <model> [--store DIR]
anomaly ls      [--store DIR]                          # list models
anomaly info    <model> [--store DIR]                  # dump metadata
anomaly serve   [--addr HOST:PORT] [--store DIR]       # run the HTTP service (M5)
```

`--store DIR` defaults to `$ANOMALY_HOME` or `~/.anomaly`. Verdicts print as
one JSON object per invocation; `batch` prints `index⇥score` (compatible with
`iforest`'s output so the two can be diffed).

## 8. Milestones

Each milestone is independently shippable, testable, and leaves the package in a
usable state. Later milestones depend only on earlier ones.

### M1 — Preprocessing & standardisation (foundation)

- `anomaly_preprocess` for numeric / categorical / timestamp with deterministic
  category ordering and the feature-order stability rule.
- `Scaler` fit/apply/free.
- Metadata struct + JSON round-trip (`std/ext/json`).
- **Deliverable:** pure functions, no I/O. **Tests:** golden feature vectors
  for mixed-type records; category-growth determinism; scaler
  fit/apply/inverse identity; zero-variance passthrough; metadata JSON
  round-trips byte-stably.
- **Depends on:** stdlib only.

### M2 — Single-version model over `iforest` (stateless core)

- Wrap `iforest_train` / `iforest_score` behind `Scaler` + feature projection.
- `decision_margin` thresholding: `score < margin ⇒ anomaly`, matching the
  reference's `predict == -1` convention.
- `anomaly_score_csv` batch path (the `iforest` CLI, but scaled + thresholded).
- **Tests:** on a synthetic dataset with injected outliers, precision/recall vs.
  a fixed expectation; determinism under fixed seed; parity of the batch report
  fields with §6.
- **Depends on:** M1, `iforest`.

### M3 — Persistence & storage backend

- Forest blob serialise/deserialise (dump/reload the `iforest` arena).
- File backend: the §4.4 layout; `store_*` interface; `model_open` load path.
- **Tests:** train → serialise → reload → identical scores (bit-exact);
  metadata + forest survive a round-trip; corrupt/partial blob is rejected
  cleanly (no UB), ASan/LSan-clean.
- **Depends on:** M2.

### M4 — Dynamic streaming model (the headline feature)

- Bounded point ring (`MAX_DATA_POINTS`), create-on-first-use, warm-up gating
  (`MIN_DATA_POINTS` → `ready = false`).
- Schedule-driven retraining (below-max / at-max frequencies).
- `model_ingest`, `model_detect_only`, `model_force_train`, `model_reset`,
  `model_delete`, `model_set_schedule`.
- **Tests:** feed a synthetic stream; assert warm-up window, retrain cadence,
  that a step-change reading is flagged after enough history, ring eviction at
  capacity, and that `detect_only` never mutates state.
- **Depends on:** M3.

### M5 — Multi-version models & fine-tuning

- Several enabled versions per model (`short_term` … `timevector`), each a
  window-filtered Isolation Forest with its own config.
- Verdict aggregation (§5.4) and the per-version breakdown.
- `model_finetune`: for each version, find the max observed score and lower the
  margin so that point is (just) anomalous, +5 % buffer — matching the reference.
- **Tests:** aggregation truth table (any-version-anomalous); per-window data
  routing; fine-tune moves the margin monotonically and makes the previously
  max-scoring point cross the threshold.
- **Depends on:** M4.

### M6 — HTTP/JSON service + CLI (interface parity)

- `src/service.nu` routes from §6; model-name validation; JSON in/out shapes
  matching the Python service.
- `src/main.nu` CLI from §7; `anomaly serve`.
- **Tests:** golden request/response fixtures captured from the Python service
  replayed against the NURL service; CLI smoke test in
  `tools/nurlpkg/test-install-tool.sh` style (`nurlpkg install anomaly`,
  ingest a few points, assert a JSON verdict).
- **Depends on:** M5.

### M7 — (optional) Autoencoder version & GPU training

- Reconstruction-error version: a small MLP autoencoder, `is_anomaly = mse >
  reconstruction_threshold`, mirroring the Python `autoencoder` version.
- Optionally route forest training / scoring through the `gpu` package for large
  models, behind a feature flag, output identical to the CPU path.
- **Tests:** reconstruction threshold behaviour on a synthetic manifold;
  CPU/GPU score parity within tolerance.
- **Depends on:** M5. Independent of M6.

## 9. Dependencies

```toml
[dependencies]
iforest = "^0.1"     # core Isolation Forest algorithm
# stdlib: vec, float, rng, sort, time, fs, ext/csv, ext/json, net (service)
```

Only `iforest` is an external package dependency; everything else is stdlib.
M7's GPU path adds an optional `gpu` dependency.

## 10. Quality bar

Matching the rest of the ecosystem:

- Leak-clean under AddressSanitizer / LeakSanitizer across every code path
  (ingest, detect-only, batch, serialise/reload, reset, delete, help,
  error/empty-input branches).
- Deterministic: a fixed seed yields byte-identical forests and hence identical
  scores across platforms and builds (inherited from `iforest`).
- Numerical parity with the reference where it is well-defined (batch scoring on
  the same data and seed; documented tolerances where floating-point order
  differs).
- The end-to-end install-and-run loop covered by the shared
  `tools/nurlpkg/test-install-tool.sh` harness.

## 11. Open questions

- **Timestamp encoding.** The reference uses raw calendar fields
  (`hour/day/month/weekday`); cyclical sin/cos encoding is better for the forest
  but diverges from the reference. Ship raw first (M1), evaluate cyclical later.
- **`contamination = auto`.** scikit-learn's `auto` sets the offset from the
  training-score distribution. Decide the exact NURL equivalent in M2 and pin it
  so scores are reproducible.
- **Window filtering for versions (M5).** The reference filters points by wall
  clock relative to *now*. For reproducible tests we need an injectable clock
  (as `std/time` supports) rather than reading the real clock inside the model.
- **Storage backend abstraction.** File backend is mandatory; confirm the
  `store_*` interface is narrow enough that a Redis/`swarm` backend could be
  added in a later package without breaking `Model`.
