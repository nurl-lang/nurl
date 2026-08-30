# anomaly — streaming anomaly detection, pure NURL

Dynamic, automatically-trainable anomaly-detection **service** over
Isolation Forests. Where the [`iforest`](../iforest) package is the kernel
(numeric matrix in, scores out), `anomaly` is everything around it: named
models that are **created on first use**, ingest one JSON point at a time,
and **train themselves** once enough history has accumulated — no offline
training step, no labels, no Python.

```
$ anomaly detect boiler temp=78.2 pressure=1.4 state=heating
{"status":"collecting","min_data_points":50,"data_points":1}
              ⋮            (50 points later the model has trained itself)
$ anomaly detect boiler temp=78.4 pressure=1.4 state=heating
{"status":"success","anomaly":false,"score":-0.012,"versions":{...},"data_points":73}
$ anomaly detect boiler temp=712 pressure=9.9 state=fault
{"status":"success","anomaly":true,"score":-0.31,"versions":{...},"data_points":74}
```

It is a NURL re-implementation of the anomaly-detection interface of a
Flask + scikit-learn reference service (`model_training.py`), with the same
HTTP routes and response shapes, so existing dashboards keep working.

## Two versions beyond the forests

- **timevector — the sliding window.** `window_size` consecutive points
  flatten to one window vector; the forest trains on window vectors and
  detection scores the window ending at the incoming point. This is the
  version that sees ORDER: a reversed pattern or a stuck sensor whose
  every reading is individually in range flags here while the point-based
  versions stay blind. Configure with `window_size` / `step_size` in the
  version config (`model_set_version_window` in the library).
- **autoencoder — the correlation detector** (trained on demand:
  `anomaly train-ae <model>` / `POST /train/autoencoder/<model>`). A
  temporary Isolation Forest first drops the ring's anomalies
  (contamination 10 %), then an MLP autoencoder
  ([`mlp`](../mlp) package: Adam, early stopping, deterministic restarts)
  learns to reconstruct the normal rows; the detection threshold is the
  95th percentile of the training reconstruction errors. It catches what
  marginals hide — a pressure/flow pair each in range but jointly
  impossible. Reported as the `autoencoder` version with the standard
  decision_function orientation (`threshold − mse`; negative ⇒ anomaly).

## What a model does

- **Heterogeneous features, encoded automatically.** Numbers pass through;
  strings become deterministic one-hot categoricals (categories kept
  sorted); ISO-8601 strings expand to `hour/day/month/weekday` calendar
  features (Python `weekday()` convention). Column types are detected on
  first sight and frozen in metadata.
- **Feature-order stability.** `feature_names` is snapshotted at each
  train; scoring projects every point onto exactly that vector (missing
  features → 0, unknown extras dropped), so one-hot columns never scramble
  between retrains.
- **Standardisation.** A persisted StandardScaler analogue (zero-mean /
  unit-variance, zero-variance features pass through) is refit over the
  full ring at each train and applied before the forest.
- **A bounded raw-point ring.** The last 150 000 points, persisted as raw
  JSON records (`data.jsonl`) — raw, so a retrain can pick up categories
  and columns that appeared after the last train.
- **Schedule-driven self-training.** Warm-up until 50 points (verdicts say
  `collecting`), then a full retrain every 50 points — every 1000 once the
  ring is full. `PUT /api/dynamic/<m>/schedule` / `model_set_schedule`
  change the cadence.
- **Multiple time-window versions.** Each model trains one forest per
  enabled version — `short_term` (180 min), `daily` (24 h), `weekly`,
  `seasonal` (90 d) and `timevector` (last 100 points) — so the same stream
  is judged against several horizons at once. A point is anomalous if
  **any** version flags it; the reported score is the most severe.
- **sklearn decision conventions.** `score` is `decision_function`:
  `-iforest_score − offset`, `offset = −0.5` for `contamination = "auto"`
  (else the 100·c percentile of training scores). A version flags a point
  when `score ≤ −decision_margin`; margins are read from live metadata, so
  tuning applies without a retrain.
- **Fine-tuning.** `model_finetune` sets each version's margin to 95 % of
  the magnitude of the worst score observed over the ring — the most
  anomalous point seen so far lands just inside the anomaly band.
- **Persistence.** `metadata.json` (types, categories, feature order,
  scaler, schedule, version configs) + one validated binary forest blob per
  version, written atomically. Corrupt or truncated files load as errors,
  never undefined behaviour. Models survive restarts.

Scores were validated against scikit-learn's `IsolationForest` on identical
deterministic data: `decision_function` values match within ~0.01 across
normal and outlier points. A fixed seed (42, the reference's
`random_state`) makes forests — and therefore scores — byte-identical
across platforms and runs.

## GPU acceleration

Bulk scoring (batch CSVs, the contamination percentile at training time,
the fine-tune ring sweep) routes through the [`gpu`](../gpu) package when
profitable (≥ 128 rows):

- On a CUDA machine the forest walk runs as a CUDA kernel.
- On a machine without a GPU, `gpu_open` falls back to the gpu package's
  **CPU backend** — the same kernel compiled by the host C++ compiler and
  parallelised with OpenMP.
- With neither (no GPU, no C++ compiler), scoring silently stays on the
  pure-NURL loop; the package behaves exactly like a pre-GPU build.

The three paths are **bit-identical by construction**: the kernel only
walks trees and accumulates f64 path lengths in the same order as the pure
loop (per-leaf `c(size)` values are precomputed on the host by the same
function the pure walker calls), and the nonlinear finish runs in NURL
either way — so which engine ran can never change a verdict, and the test
suite asserts element-for-element `==` across engines. Measured on 200 000
rows × 300 trees: pure NURL 9.6 s, host C++ backend 1.1 s (~9×), RTX 4090
213 ms (~45×). `ANOMALY_GPU=0` disables the accelerator; `NURL_GPU=cpu`
forces the CPU backend on a CUDA machine.

**Autoencoder training** (`/train/autoencoder/<model>`) also runs on the
GPU by default when a CUDA device is present — and training is where the
autoencoder's time goes (the scoring passes are milliseconds). The device
mirror (`src/aegpu.nu`) keeps the training loop on the host (same seeded
shuffles, validation split, early stopping, restarts) and reproduces the
CPU's floating-point rounding and accumulation order in its kernels, so the
GPU-trained network is **bit-for-bit identical** to the CPU-trained one —
same weights, same p95 threshold, same verdicts, just **~34× faster**
(6 k rows × 12 features, 64-32-64, 3 restarts: 7.6 s → 0.22 s on an
RTX 4090). Without a CUDA device (or with `ANOMALY_GPU=0`) training uses
the pure `mlp` path — the same result at CPU pace.
`tests/aegpu_parity_test.nu` asserts the bit-identity: weights, biases,
the full Adam state, epoch count and losses.

## CLI

```
anomaly detect <model> key=val ...     # ingest one point → verdict JSON
anomaly score  <model> key=val ...     # score only (never ingests/retrains)
anomaly batch  [-f FILE] [-H] [-m M]   # stateless CSV scoring (index⇥score)
anomaly train  <model>                 # force a retrain now
anomaly reset  <model>                 # drop data+forests, keep the name
anomaly rm     <model>                 # delete the model entirely
anomaly ls / info <model>              # list models / dump metadata
anomaly serve  [--addr HOST:PORT]      # run the HTTP/JSON service + dashboard
               [--webroot DIR]
```

The store defaults to `$ANOMALY_HOME`, else `~/.anomaly`; override per
command with `--store DIR`.

## HTTP service

`anomaly serve` exposes the reference routes:

| Route | Meaning |
| --- | --- |
| `POST /detect/<model>` | ingest one point, train if due, verdict (202 while warming) |
| `POST /detect_only/<model>` | score only — no ingestion, no retrain, no writes |
| `GET\|POST /force_train/<model>` | retrain now |
| `POST /detect_anomalies` | batch-score a CSV file (`{"file_path": ..., "has_header": ...}`) |
| `GET /models/dynamic` | list models with metadata |
| `GET /models/dynamic/<m>/metadata` | model metadata, plus the autoencoder's own state |
| `PUT /models/dynamic/<m>/metadata` | edit the schedule and the per-version configs (see below) |
| `GET /models/dynamic/<m>/data?limit=N\|all` | recent raw points |
| `POST /models/dynamic/<m>/reset` | drop data + forests, keep the name |
| `DELETE\|GET /delete_model/<m>` | delete entirely |
| `PUT /api/dynamic/<m>/schedule` | `{"below_max_retrain_frequency": .., "at_max_retrain_frequency": ..}` |
| `POST /api/dynamic/<m>/finetune` | recalibrate decision margins |
| `POST /train/autoencoder/<m>` | train the autoencoder version — optional `{"hidden": [..], "contamination": x}` |

Model names must match `^[a-zA-Z0-9_]+$`. The router is a plain function
over `HttpRequest` — the test suite drives every route without a socket.

### Editing the metadata

`PUT /models/dynamic/<m>/metadata` takes the *editable half* of the
metadata. Every key is optional, but at least one must be present, and
every field inside is optional too — what the patch omits keeps its value,
so a checkbox can send one field:

```jsonc
{
  "schedule": { "below_max": 50, "at_max": 1000 },
  "max_data_points": 50000,                        // ring size; see below
  "versions": {
    "weekly":      { "enabled": false },          // stop scoring, drop the forest
    "daily":       { "decision_margin": 0.2 },    // effective at the next detect
    "seasonal":    { "n_estimators": 500 },       // effective at the next retrain
    "hourly":      { "window_minutes": 60 }       // an unknown name ADDS a version
  },
  "replace_versions": false                        // true ⇒ omitted versions are deleted
}
```

Which top-level keys are accepted is not something a client has to know
in advance: every metadata response carries `editable_fields`, the same
list the patch reader works from. The dashboard's editor is generated from
it, which is why `max_data_points` appeared there the moment the service
started accepting it.

`max_data_points` is the size of the ring of raw points the model keeps
(150 000 by default, and at least `min_data_points` — a smaller ring could
never warm the model up). Lowering it below the current fill evicts the
oldest points and rewrites the log **before the call returns**, so the new
cap holds at once instead of converging on it one ingest at a time.

The response echoes the whole updated metadata. Two fields bite
immediately — `enabled` and `decision_margin`; the geometry
(`window_minutes` / `window_points` / `window_size` / `step_size`) and the
forest size (`n_estimators` / `max_samples` / `contamination`) take effect
at the next retrain, so a config change can never desync a trained forest
from the scoring path. Values are clamped into a trainable range rather
than rejected.

Disabling a forest version **deletes its forest**: its verdict is gone from
the next detect and re-enabling it costs a retrain. That is deliberate —
a kept blob would be resurrected trained against a feature order and scaler
the model has since moved past. The `autoencoder` version is only *muted*:
its net carries its own frozen feature order, stays valid across retrains,
and is far too expensive to throw away on a checkbox.

The *learned* half of the metadata — column kinds, category vocabularies,
the authoritative feature order and the scaler — is never accepted from a
client. It is refitted at every train, and a hand-written copy would
silently desync every forest.

## Dashboard

`anomaly serve` also serves a small self-contained web dashboard (no CDN, no
build step — plain HTML/CSS/JS that talks to the routes above):

| Page | What it does |
| --- | --- |
| `/` · `/modelmanager.html` | list models, train / finetune / reset / delete, toggle versions and retune their margins, train the autoencoder, edit the retrain schedule — or, under *Advanced*, the whole editable metadata, as a generated field form or as raw JSON |
| `/modeltrainer.html` | feed points (`/detect`) one at a time or in bulk (paste JSON lines / generate synthetic), force-train |
| `/visualize.html` | plot any numeric feature of a model's stored points over time |
| `/anomalies.html` | re-score stored points via `/detect_only` and highlight the anomalies (chart + table with the flagging versions) |

The HTML lives in `static/` next to the package. `serve` locates it via, in
order: `--webroot DIR`, `$ANOMALY_WEBROOT`, `<exe-dir>/static`,
`<exe-dir>/../share/anomaly/static`, then `./static`. If none exists the
server runs API-only (dashboard routes return 404) and logs which web root it
picked on startup.

## Library

```nurl
$ `deps/anomaly/src/dynamic.nu`

: Store st ( store_open `/var/lib/anomaly` )
: *Model mo ( model_open st `boiler` )
: !Verdict String vr ( model_ingest mo point_json )   // or model_detect_only
```

`model_open / model_ingest / model_detect_only / model_force_train /
model_reset / model_delete / model_finetune / model_train_autoencoder /
model_set_schedule / model_set_margin / model_set_version_enabled /
model_set_version_window / model_apply_meta_patch / model_metadata /
model_free`, plus the layers beneath:
preprocessing + scaler (`prep.nu`), the per-point decision core over
`iforest` (`model.nu`), bulk/batch scoring + training with the GPU path
(`score.nu`), persistence (`store.nu`), batch CSV (`csvdata.nu`) and the
HTTP surface (`service.nu`). Every mutating entry point has an
`_at` variant taking `now` in unix seconds — the injectable clock that
makes window filtering reproducible in tests.

## Known divergences from the Python reference

Deliberate, all documented in the code:

1. **Fine-tune implements the intent, not the bug.** The reference
   initialises its accumulator to `-inf` and only updates on `score <
   -inf`, so it never adjusts anything (and its "+5 % buffer" comment
   belies a `* 0.95`). We track the true minimum and apply `0.95·|min|`,
   in place (no `tune_<name>` clone).
2. **One scaler per model**, fit over the full ring — the reference fits
   one per version and silently keeps whichever trained last.
3. **Retraining is keyed on the lifetime point counter**, so it keeps
   working at ring capacity (the reference's count-based fallback arms a
   threshold above the capped length; its per-version timers are what kept
   it retraining).
4. **`timevector` trains a forest on the last 100 points** rather than on
   flattened 100-point sliding windows (which bypassed the scaler in the
   reference).
5. **`/detect_anomalies` self-trains on the file** — the reference's
   separate "static model" family doesn't exist here; passing `model_name`
   is a 400 rather than silently using a different model family.
6. **Points store raw JSON lines** (`data.jsonl`), not a pickled array —
   raw records are what let retrains learn new categories.

## Tests

`./tests/anomaly_test.sh` builds and runs the seven unit suites (165+ checks:
preprocessing golden vectors, sklearn-parity decision maths, bit-exact
blob round-trips, corrupt-file rejection, streaming mechanics, window
routing, fine-tune, all HTTP routes, GPU/CPU-backend bit-parity), a CLI
end-to-end pass, and a live served-over-curl smoke test. The whole suite is AddressSanitizer /
LeakSanitizer-clean (`NURL_SAN=1 ./tests/anomaly_test.sh`).
