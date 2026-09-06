# `anomaly` — streaming anomaly-detection service (specification)

Status: **implemented (M1–M6, v0.1.0).** §8's milestones M1–M6 are shipped
and tested; M7 (autoencoder / GPU) remains open. Where the implementation
deliberately diverges from this draft or from the Python reference, the
divergence is listed in README.md ("Known divergences") — notably the
point log is raw JSON lines (`data.jsonl`, §4.4) rather than a binary
matrix, so retrains can learn categories that appeared after the last
train.

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
| `GET  /models/dynamic/<model>/data` | recent data points (`limit=N`, `all`; `at=<index>` one stored row) | † |
| `GET  /models/dynamic/<model>/export` | the stored points as a file: `format=csv\|jsonl`, the same `from`/`to`/`last`/`fields`/`limit` as `/data`, whole ring by default; `Content-Disposition: attachment`, `X-Rows` | † |
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
- `MAX_DATA_POINTS = 150000` — ring capacity a NEW model starts with. It is
  per-model metadata, not a constant: `max_data_points` is editable (§6) and
  persists with the model.
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
- **timestamp** — ISO-8601 parsed via `std/time`, read in the model's
  time zone; expands to `col_hour_sin/cos`, `col_weekday_sin/cos`,
  `col_month_sin/cos` (encoding 2, `ANOM_FEAT_ENC`; encoding 1 was the
  linear UTC `hour/day/month/weekday`, and a model trained under it keeps
  it until its next retrain, reporting `retrain_required`). A cycle is
  emitted only when the rows of the last train covered it twice
  (`__an_cycle_seen` over `Meta.train_span`: hour needs two days, weekday
  two weeks, month two years; an unknown span keeps every cycle) — a cycle
  the data has not been round twice is a date, and a month feature over
  eight days splits them into before and after.
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
  "schedule":        { "below_max": 50, "at_max": 1000,
                       "autoencoder": false },  // true ⇒ the AE retrains with the forests
  "versions":        { version_name: <version config>, ... },
  "n_points_seen":   int,  // lifetime; keeps climbing past the cap
  "n_points_stored": int,  // rows in the ring now (≤ max_data_points)
  "last_trained_at": int,  // point count at last train
  "max_data_points": int,  // ring capacity, editable (§6)
  "clock":           "time" | "count"   // §5.8; editable only while empty
}
```

**Editable vs learned.** `schedule`, `max_data_points` and `versions` are the user's to set
(§6, `PUT /models/dynamic/<m>/metadata`, `model_apply_meta_patch`); everything
else — `column_types`, `categories`, `feature_names`, `scaler` — is learned at
each train and is never accepted from a client, because a hand-written copy
would desync every trained forest. Within a version config, `enabled` and
`decision_margin` take effect at the next detect; the window geometry and the
forest size take effect at the next retrain. Disabling a forest version deletes
its forest blob, so re-enabling costs a retrain; the `autoencoder` version is
only muted, because its net carries its own frozen feature order.

**Feature-order stability rule.** `feature_names` is authoritative once a model
is first trained. At scoring time a point is projected onto exactly that vector:
missing features default to `0`, unknown extras are dropped. This mirrors the
reference (`model_features` in metadata) and is what keeps categorical one-hot
encodings aligned across retrains.

### 4.4 On-disk layout (file backend)

```
<model_dir>/<name>/
  metadata.json            # §4.3
  data.jsonl               # ring of recent RAW points, one JSON record per
                           # line, each stamped with its ingest `timestamp`
                           # (raw — not projected vectors — so a retrain can
                           # pick up new categories/columns)
  version_<v>.forest       # one compact forest blob per enabled version
  autoencoder.json         # the trained autoencoder, if one exists
  scores.bin               # cached per-point verdicts, stamped with the
                           # model's score_epoch (§5.6) — pure derived
                           # state: deleting it costs a rescan, never a
                           # wrong answer
  labels.jsonl             # what readers said about points (§4.5): one
                           # record per line, appended, keyed by the
                           # point's LIFETIME sequence number, last
                           # write wins; `none` withdraws

<root>/orgs/<org>.db       # one SQLite database per organisation (§5.7):
                           # users + roles, model ownership, API keys.
                           # The org is IMPLICIT in the filename, so no
                           # query carries an org column and none can
                           # forget one.
```

The forest blob is a straight serialisation of the `iforest` node arena (§the
arena is already flat, so this is a length-prefixed dump of the SoA arrays plus
the per-tree root indices). The storage API is an interface (`store_*` fns) so a
non-file backend can be dropped in without touching callers.

### 4.5 Labels

A reader's word on a stored point: `false_positive` (it was flagged and
nothing was wrong), `confirmed` (it was the real thing), `none` (withdraw).
`Label { seq, ts, label, by, at, note }` is appended to `labels.jsonl` as one
JSON record per line; `store_load_labels` replays the file and keeps the last
record per `seq`, dropping a `none`. The key is the point's LIFETIME
sequence number (`Meta.n_seen` space, the same the score cache aligns on),
not its ring index: eviction shifts every index and a label on an index would
migrate to whichever row took the slot. `model_seq_base` (n_seen minus the
rows held) turns one into the other; `model_label_map` joins the labels in
force onto the ring, a row past the ring being simply unlabelled. Labels
change no verdict, so they never bump the score epoch. Their reader is
`model_calibrate`, which leaves labelled false positives out of the rows a
margin is fitted on and reports them as `excluded` (fine-tune inherits it)
— a margin should not be paid for by rows already known to be noise. A
reset drops the file with the ring, since the sequence numbers start over.

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
| `( model_calibrate model from to )` | `CalReport` — per version, the sorted decision values of the ring rows in `[from, to]` (0 = unbounded), what the current margin flags, and `cal_margin_for_rate` to read the margin for any alert rate off them |
| `( model_finetune model )` | `FineTuneReport` — set every enabled version's margin to the one that flags `ANOM_FT_RATE` (1 %) of the last `ANOM_CAL_WINDOW` (24 h, anchored on the newest stored point) |
| `( model_finetune_at model rate from to apply only )` | the same with the rate, the window, a dry run (`apply = F`) and a version filter (`only`, empty = all) |
| `( model_label_point model index label by note at )` | the row's sequence number after recording a label (§4.5); −1 for an index outside the ring, −2 for an unknown label |
| `( model_labels model )` / `( model_label_map model labels )` | the labels in force; per ring row the index of its label, −1 for none |
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
  score:      f       // the most severe version's score (its own units)
  severity:   f       // that version's severity — the aggregate
  versions:   Vec VersionVerdict   // per-version { name, anomaly, score,
                                   //               margin, cfg_margin,
                                   //               feat }
}
```

`feat` is the feature index a verdict is about, −1 for every version but
the **range guard**: `range_guard` is a forestless version whose decision
value is `−max_j |z_j|` over the standardised features (the shared scaler
the last retrain fitted), so `score <= −margin` reads "some feature is
`margin` or more standard deviations from its training mean" and the
margin is a sigma count (`ANOM_GUARD_SIGMA`, 4.0, by default; `units` in
the service says `standard_deviations`). It is the univariate check the
forests structurally cannot make — a single reading at ten sigma is one
coordinate among many to a tree — and it names the feature. It is in
`meta_default_versions`; a model from before it existed gains the VerCfg
at its next retrain (`__an_ensure_guard_cfg`), where the epoch bumps and
the metadata is saved anyway, so the score cache's version bitmask never
shifts under a live cache. Disabling it mutes it, like the autoencoder:
there is no forest to drop and nothing to retrain on re-enable.

`missing` (service verdicts) lists the columns the model knows and the
point left out: they are scored as 0 after standardisation — the training
mean — so a point is never refused for a gap in the stream, but the reader
is told. `model_detect_only` is the exception: a bare question about a
point carries the whole point, so it fails with the columns named.

The **flatline guard** (`flatline`) is the second forestless version and
the other check the forests cannot make: a sensor that has stopped moving
sits inside its training range, so every per-point score stays quiet.
Each retrain fits two references per numeric feature from the
standardised training matrix (`__an_flat_fit`; `flat_run`, `flat_sd` in
`Meta`, serialised under `flatline`): the longest run of identical values
and the `ANOM_FLAT_QUANTILE` (0.05) quantile of the standard deviation over
sliding windows of `window_size` points (`ANOM_FLAT_WINDOW`, 60, the
VerCfg's `window_size`). At scoring, the tail of the ring ending at the
point gives each feature a run fraction `run / max(W, 2·ref_run)` — a
feature that legitimately sits still for `ref_run` points in training
needs twice that before it counts — and, while the run is still shorter
than `W` and the reference is positive, a collapse `1 − sd_window /
ref_sd`, which catches the gauge that dithers in its last digit rather than
repeating a value. The decision value is `−max` over the numeric features
and `feat` names the one, so `score <= −margin` with the default
`ANOM_FLAT_MARGIN` 0.9 reads "a column has been flat for 90 % of its
window" (`units` is `fraction`). Features without a reference (a ring
shorter than `W` at retrain, a non-numeric column) are not watched, so
`model_scan_versions` lists the version only once it has been fitted.
Fine-tune leaves its margin alone — a rate target would only ever loosen
it, since a stuck column is rare in a healthy training set — while
calibration still reports it; `edit_model` sets it. A column missing for a
stretch reads as flat (its standardised value repeats), which is what a
person would call it too.

`severity = −score / margin` (`anom_severity`; `margin = 0` gives 1.0 when
flagged, 0.0 otherwise) is computed for every version verdict; the
aggregate is the maximum over versions and `score` is that version's
decision value — never a plain minimum over versions, which would let a
forest's ~1e-1 always outrank the autoencoder's ~1e-4 and hide the joint
model's alarm. The scan rows carry the same pair, and the score cache
(`ANOMSCR2`) stores both. 1.0 is exactly the alert line, 2.0 twice as far
past it, negative comfortably normal — the one unit-free number an operator
or an agent can compare across versions and models.

Aggregation: a point is anomalous if **any** enabled version flags it; the
reported `score` is the most-severe version's score. (The reference checks all
versions and surfaces each; §6 preserves that in the JSON.)

`margin` is the *effective* band the score was compared against, so the rule
`score <= -margin ⇒ anomaly` holds for every version without exception;
`cfg_margin` is the number stored in the metadata. They differ only for the
autoencoder — see §5.5.

### 5.5 The autoencoder's decision margin is relative

Every forest version's `decision_margin` is an absolute offset on a
`decision_function` whose scale is fixed by sklearn's convention: normal points
sit near 0, anomalies below it, so `0.06` means the same thing for every model.

The autoencoder's score is `reconstruction_threshold − mse`, and MSE has no
such fixed scale: it is the mean squared error of MinMax-scaled features and
lands wherever the data puts it — ~1e-3 for one model, ~2e-4 for another.

The Python reference applies its shared absolute-margin rule to the
autoencoder anyway. `model_training.py` computes `is_anomaly = mse >
reconstruction_threshold` inside the autoencoder branch, and thirty lines
later — at the same indentation as the branch itself, so unconditionally —
overwrites it with `is_anomaly = bool(score <= -decision_margin)`, using the
autoencoder's default margin of `0.05`. Against a threshold of ~5e-4 that
demands a reconstruction error a *hundred times* the p95 of the training
errors, which mutes the only version that models the joint distribution. The
reference ships that version `"enabled": False`, so the muting was never
noticed. (This is a second bug of the same family as the fine-tune one in
§5.2: code whose stated intent the surrounding lines quietly undo.)

We keep the knob and put it on the only scale that travels between models:
for the `autoencoder` version, `decision_margin` is a **fraction of the
model's own reconstruction threshold**.

```
effective_margin = reconstruction_threshold * decision_margin
anomaly          ⇔ decision_function <= -effective_margin
                 ⇔ mse >= reconstruction_threshold * (1 + decision_margin)
```

The stored default `0.05` therefore now reads "flag at 5 % above the p95
training error" — the documented intent — instead of "flag at p95 + 0.05",
and the same number means the same thing on every model. Existing metadata
needs no migration: the value that was mute becomes the value that works.

`model_calibrate` and `model_finetune` (§5.2) cover the autoencoder on the
same rule as the forests, in these relative units: its decision values are
expressed as `decision_function / reconstruction_threshold`, so the margin
that flags 1 % of the window is read off the same sorted list as a forest's.

**Fine-tune is a rate, rounded to be readable.** For a version with `n`
window rows sorted ascending (`dfs`) and a target rate `r`, `k = round(r·n)`
and the raw margin is `−dfs[k−1]` (`k = 0`: just above the worst row). The
written value is that margin rounded to the fewest significant digits — 2 to
5, nearest first, then away from the target side — whose flagged count stays
within `k/10` of `k`, falling back to 6 digits rounded toward the target
side. So `0.12994712` becomes `0.13` when the data allow it, and never
`0.1299471200000001`. Ties in the data can put the actual count above `k`;
the report says what was flagged before and after.

**The `autoencoder` version config is never a forest.** The retrain loop
skips it and deletes a stale `version_autoencoder.forest`, and the loader
ignores one: a zero-tree forest scored under that name would be a second
"autoencoder" verdict reading the relative margin as an absolute one.

### 5.6 Scanning the stored ring

Re-scoring stored history is pure recomputation — the same point against the
same forests yields the same verdict every time — so it is cached.

```
model_scan_at(mo, from_ts, to_ts, limit, force) -> ScanOut {
  pts:        Vec ScoredPt { idx, ts, score, anomaly, present, flagged }
  vnames:     Vec String        // the bitmask order for present/flagged
  epoch, total, considered, hits, misses, anomalies
}
```

`present` and `flagged` are bitmasks over `vnames`, so "this version had no
verdict" (a timevector window longer than the ring prefix) stays
distinguishable from "this version was clean".

**Invalidation is by epoch, not by rule.** `Meta.score_epoch` is bumped by
anything that can change a verdict — a retrain, a new autoencoder, a margin
edit, a version toggled on or off, a metadata patch, a reset — and a cache
entry stamped with an older epoch is stale by construction. There is no
per-entry invalidation logic to get wrong.

**Alignment survives ring eviction** because cache rows are keyed on the
lifetime point counter, not the ring index: `base_seen` is the lifetime index
of row 0, so ring row `j` of a ring of length `L` at counter `S` lives at
cache index `S − L + j − base_seen`. Rows outside the stored span are misses,
never mismatches.

A replayed verdict must not see the future: `__an_score_enc_upto` scores a
point as though it sat at its own ring position, so a timevector window is
built from the points *before* it. A scan therefore reproduces
`detect_only` exactly.

### 5.8 The clock of a model

Every stored point carries an `i` timestamp, and every window in this
package — the four forest versions' `window_minutes`, calibration's and
fine-tune's `last`, the scan's `from`/`to` — is a span of those stamps. A
model has one of two clocks (`Meta.count_clock`, JSON `clock`):

- **`time`** — the stamps are Unix seconds: the point's own `timestamp`, or
  the wall clock when it arrives without one. Windows are durations.
- **`count`** — the data has no timestamps and the model refuses to invent
  any. The n-th stored point is stamped `n × ANOM_TICK` (60), whatever the
  wall clock says, so every duration in the package is a *number of
  points*: a version's `window_minutes` is a point count, `last=N` is the
  newest N points (span `N × 60 − 1`, the lower bound being inclusive), and
  a dashboard shows the stamp as the ordinal `#n`. Nothing time-of-day
  shaped is ever derived — no calendar features, no "last 24 h" in the
  wall-clock sense.

The clock is chosen when the first points land — an import of unstamped
rows makes a count-clock model, of stamped rows a time-clock one, and
`?clock=` overrides — and is editable through the metadata only while the
model holds no points, because a stored ring on the wrong clock would put
every window in the wrong unit. On a settled clock later rows conform:
stamps landing on a count clock become ticks, unstamped rows on a time
clock take the clock time, and the import reports both in `notes`.

The 60-second tick is not a claim about the data's cadence. It only makes
minute-denominated windows and point counts the same number, so a
`window_minutes: 180` forest is the last 180 points on either clock.

### 5.7 Identity, organisations and ownership (`src/authz.nu`)

The service was single-user by construction: every route reached every model
in one flat store. Three concepts turn that into a shared service without
moving a stored model.

**Off by default.** With `ANOMALY_AUTH` unset, `authz_principal` returns an
authenticated admin of the reserved `local` organisation and every gate opens.
An upgraded binary must not start refusing the requests its predecessor
served. `ANOMALY_AUTH=1` without both an issuer and a client id also stays
off: half-configured, verification would refuse everything rather than protect
anything.

| Concept | Definition |
| --- | --- |
| identity | an OIDC bearer token, verified by `packages/oauth` against the provider's JWKS |
| organisation | the `tid` claim, or the issuer when a provider publishes none → `<store>/orgs/<org>.db` |
| owner | a row in that database binding a model name to a subject |

```
Principal { authed, via_key, org, sub, email, pname, role, key_id }
```

An org id becomes a filename, so it is not taken on trust: a plain GUID
passes through lowercased, anything else is replaced by a 32-character digest
of itself. No input can produce a separator, a `..` or an empty name.

**Roles.** `admin` sees and manages the organisation's models, users and keys;
`viewer` sees only what it owns. The first subject to authenticate from an
organisation becomes its admin — nobody else could have granted it — and
`az_user_set_role` refuses to demote the last one, because an organisation
with no admin can never appoint another.

**Ownership.** A model with no row is *unowned*: what everything created
before this section existed looks like, and what a model ingested through the
open window (below) looks like. Unowned models are visible to admins so
somebody can claim them, rather than being absorbed by whoever signed in
first. Deleting a model forgets its row, or the next model to reuse the name
would inherit an owner nobody chose.

**API keys** (`anok_<16 hex id>_<64 hex secret>`) carry the identity and role
of the user who created them, so "you see only your own models" holds for a
machine exactly as it holds for that user's browser. Only a SHA-256 of the
secret is stored. A presented key names no organisation, so it is tried
against each database in `<store>/orgs`; with one database per tenant and a
key arriving a few times a minute, the scan is cheaper than a second index
that could disagree with the first.

**The migration window.** `ANOMALY_OPEN_INGEST` (default on) keeps `/detect`
and `/detect_only` reachable without credentials while already-deployed
producers are moved onto keys, so enabling authentication drops no data. It is
a window, not a design: with it open, anyone who can reach the port can write
points.

**The gate.** Every handler starts with one, so no handler assembles a policy
decision out of parts and a route added later cannot forget half of one.

```
__an_gate_auth   (req, need_admin)          -> Gate   // is there a caller
__an_gate_model  (req, name, allow_create)  -> Gate   // may it touch this model
__an_gate_ingest (req, name)                -> Gate   // the window above
```

`allow_create` marks the routes that bring a model into existence: a model
with no stored directory has no owner yet, and refusing there would mean only
administrators could ever create one.

`oauth`'s `with_oidc_bearer` returns a one-argument handler that the router
used here does not accept, and every route needs its own ownership decision
anyway, so the gate calls `oidc_request_identity` directly. Two audiences are
tried — the configured API audience, then the client id — because a dashboard
that sends either token from the same sign-in is a dashboard that works.

## 6. HTTP/JSON service surface (`src/service.nu`, optional milestone)

The routes mirror §3 (ported column). Request/response shapes match the Python
service so existing dashboards and the `modelmanager` UI keep working:

- `POST /detect/<model>` body = `{ col: value, ... }` (numeric/categorical/
  timestamp), optional `timestamp`. Response = `Verdict` as JSON — `anomaly`,
  `score`, `severity`, `data_points` — with the `versions` map (per version
  `anomaly`, `score`, `severity`, `threshold_info { margin, decision_margin,
  units }`: `margin` is the absolute band the score was compared to,
  `decision_margin` the stored setting, and `units` says whether that
  setting is `absolute` on the decision function, `standard_deviations`
  for the range guard, `fraction` for the flatline guard, or, for the
  autoencoder, `relative_to_threshold`; the two guards' entries also
  carry `feature`, the one they judged by),
  `status`, `model`, echoed `data_point`.
- `POST /detect_only/<model>` — same body, `Verdict`, no state change.
- `POST /detect_anomalies` body = `{ file_path, model_name? }` → batch report:
  `anomaly_count`, `anomaly_percentage`, `anomaly_indices`, `has_anomalies`,
  `anomaly_details` (first 100).
- `GET /models/dynamic/<model>/metadata` — §4.3 metadata plus an
  `autoencoder` block (its own state lives in `autoencoder.json`, not the
  metadata): `trained`, `enabled`, `reconstruction_threshold`,
  `training_data_points`, `filtered_anomalies`, `decision_margin` (a
  fraction of the threshold, §5.5), `effective_margin` (threshold ×
  decision_margin — the band in the score's own units), `feature_names`, `layer_sizes`, `prefilter_contamination`, `trained_at`,
  `retrain_with_forests`. Every metadata response (this one, the
  listing, and the PUT echo) also carries `editable_fields`: the top-level
  keys the PUT below accepts, published so a client never has to keep its
  own copy of the list. It is service-shaped and deliberately absent from
  the stored `metadata.json`.
- `PUT /models/dynamic/<model>/metadata` body = `{ alias?, schedule?,
  max_data_points?, versions?, replace_versions? }`, every field within
  optional (an omitted field keeps its value; an unknown version name adds
  a version; `replace_versions` deletes the versions the object omits).
  `max_data_points` is the raw-point ring size: it must be positive and at
  least `min_data_points`, and lowering it below the current fill evicts
  the oldest points and rewrites the log before the response, so the cap
  holds immediately rather than converging one ingest at a time. 400 on a
  shape that is not a JSON object of objects, on a rejected
  `max_data_points`, or on an empty patch. Response echoes the full
  metadata.
- `GET /models/dynamic/<model>/anomalies` — the scan of §5.6, served from
  one model load. Query: `from` / `to` (unix seconds), `last=<seconds>`
  (relative to `to`, else to the newest stored point — never to the server
  clock, so a model that stopped receiving data still answers "the last
  24 h *of it*"), `limit` (newest N of the window; `all` for no cap),
  `only=anomalies`, `votes=N` (a row is an anomaly only when N or more
  versions flagged it; default 1), `versions=a,b`, `fields=x,y` (attach
  these feature values), `contrib=N` (top-N autoencoder contributors per
  flagged point, `0` to omit), `group=runs` (list the events, below),
  `refresh=1` (ignore the cache). Response:
  `data_points_count`, `considered`, `anomalies`, `votes`, `runs`, `returned`,
  `model_versions`, `flagged_by_version { name: rows }` (over the whole
  window, before any filter), `window { from, to, one_time }` (`one_time`:
  every row of the window carries one stamp — a file imported without its
  time column named — so the time-window versions all see one instant),
  `cache: { hits, misses, epoch }` and `points`, each
  `{ index, timestamp, score, severity, anomaly, votes, run?, versions[], values?, contributions? }`,
  a contribution being `{ feature, error, share, value, expected }` — the
  value the point carried and the autoencoder's reconstruction of it.
  String parameters are percent-decoded, so a feature named
  `Ilman lämpötila [°C]` can be asked for. `considered` and `anomalies`
  describe the whole window, so a filtered response still says how much it
  filtered; `anomalies` counts the rows that reached `votes`, so with
  `votes=2` on a three-version model it is the count the versions agree
  on, and a row's own `votes` is how many flagged it.

  A **run** is a maximal sequence of consecutive stored rows every one of
  which is an anomaly under `votes`: a burst is one event to whoever reads
  the list, and a marginal 1 % says nothing about whether it is a hundred
  single rows or three bursts. `runs` counts them over the window, an
  anomalous row's `run` is its number (1-based in ring order; the count and
  the numbers are computed over the whole window, before `limit` and
  `versions` narrow the rows), and `group=runs` adds `events`, one per run:
  `{ run, rows, from_index, from, to_index, to, worst_index, worst_score,
  worst_severity, versions[] }` — `worst` being the row of highest severity,
  `versions` the union of the rows' flagging versions. The dynamic layer
  computes them with `scan_runs` over a `ScanOut` (§5.6).
- `GET /api/auth/config` — public, because the page that has not signed in is
  the one asking: `enabled`, `issuer`, `client_id`, `audience`, `scope`,
  `redirect_path`, `open_ingest`. Everything in it is in the redirect the
  browser makes anyway; publishing it is what stops the dashboard carrying a
  second, drifting copy of the deployment's identity configuration.
- `GET /api/me` — the caller's identity, organisation and role.
- `GET /api/org/users`, `PUT /api/org/users/<sub>/role` — the roster (admin).
- `GET|POST /api/org/keys`, `DELETE /api/org/keys/<id>` — API keys. The POST
  response carries the only copy of the secret there will ever be.
- `POST /models/dynamic/<model>/claim` `{ owner? }` — set a model's owner
  (admin); defaults to the caller.
- `POST /train/autoencoder/<model>` optional body = `{ hidden?: [int],
  contamination?: float }` → `training_data_points`, `filtered_anomalies`,
  `reconstruction_threshold`, `layer_sizes`. `hidden` absent or empty keeps
  the layout a trained net already has (a first train uses 64-32-64). Both
  are stored with the net and reused when `schedule.autoencoder` retrains
  it with the forests.
- `POST /models/dynamic/<model>/import?format=csv|json|jsonl|fmi|auto` —
  the body is the file (`fmi`, the name the weather service's export comes
  under, is the CSV reader; an unknown format is 400 naming the four). The rows' time is read before any lands:
  `?inspect=1` returns the columns (`name`, `kind`, `filled`, `sample`)
  and a proposal `time { mode: column|parts|none, column | parts { year,
  month, day, clock | hour, minute, second }, confidence, reason, sample,
  sample_unix }` without creating the model (`model { exists, data_points,
  clock }`). The import then takes the plan back as `?time=<json>`
  (`{"mode":"auto"}` = the proposal), the zone naive stamps are read in as
  `?tz=local|utc|±HH:MM`, `?calendar=1` to keep an ISO `time` column for
  calendar features, and `?clock=time|count` for a new model (§5.8).
  Recognised as a stamp under any column name: ISO 8601 / RFC 3339, the
  Postgres and MySQL `TIMESTAMP` / `TIMESTAMPTZ` forms, `YYYYMMDDTHHMMSS`,
  Unix seconds / milliseconds / microseconds / nanoseconds, a bare date;
  as parts, year/month/day/hour/minute/second columns under English or
  Finnish names (`Vuosi`, `Kuukausi`, `Päivä`, `Aika`, …). The consumed
  columns are dropped so a year never becomes a feature; `-`, `NA`, `null`
  and their kin are missing values in a JSON row as in a CSV cell
  (`__imp_norm_row`: JSON `null` and the markers are dropped, a number
  quoted as a string is a number), so the three readers hand the model
  the same record. Response adds `clock` and `time {
  …plan, stamped, failed, first_failure? }`.
- `POST /models/dynamic/<model>/labels` — body `{ index, label, note? }`,
  `label` one of `false_positive`, `confirmed`, `none` (withdraw). Records
  what a reader said about the stored row at `index` (§4.5): the row's
  lifetime sequence number, its timestamp, the label, who (the principal's
  name, else email, else `key:<id>`, else subject), when, the note. 400
  for an unknown label or an index outside the ring; write access to the
  model, as fine-tune. Verdicts do not change, so the epoch does not move.
  Response echoes the record with `index` and `seq`.
- `GET /models/dynamic/<model>/labels` — the labels in force: `count`,
  `false_positives`, `confirmed`, `labels[] { seq, timestamp, label, by,
  at, note, index | evicted }` — `index` the row's current ring index,
  `evicted: true` when the ring has let the row go.
- `GET /models/dynamic/<model>/calibration` — §5.2 `model_calibrate` over
  the same window query as the scan (`from` / `to` / `last`, default the
  last 24 h of stored data, `last=all` the whole ring; on a count clock
  `last` is a number of points, default 1440), read-only. Response:
  `window { from, to, rows, excluded, total }` (`excluded`: rows in the
  window labelled false positives, left out of every number below), `aggregate { flagged, rate }` and per
  enabled, trained version `{ units, margin, n, flagged, rate, worst, median,
  margin_for_rate: { "0.1%": { margin, flagged, requested_rate,
  achieved_rate, exact }, "0.5%", "1%", "2%", "5%", "10%" }, curve: [[rate,
  margin], …] }` — 110 points, 0.1 % steps to 1 % then 1 % steps to 100 %,
  so a dashboard can turn a typed margin into an estimated alert rate
  without a round trip. `curve=0` omits it. 400 on an untrained model.
  `margin` is the stored value verbatim, and every number of a version is
  in its `units`: `absolute` decision values for a forest,
  `standard_deviations` for the range guard, `fraction` for the flatline
  guard, `relative_to_threshold` for the autoencoder (its scores divided
  by the reconstruction threshold, §5.5). A sorted list of decision values
  can only supply margins at its gaps: when the requested count falls in
  a run of tied values (a stuck sensor, whole days of identical points)
  `cal_margin_for_rate` answers with the nearer edge of the run — the
  rows before it, or the run whole (on a tie between the edges, whole) —
  and `achieved_rate` / `exact` say what that came to.
- `POST /api/dynamic/<model>/finetune` body (all optional) = `{ rate: 0.01,
  last: 86400 | "all" | "own", from, to, dry_run: false, versions: [names] }` →
  `rate`, `dry_run`, `window { from, to, rows, own }`, per version `{
  units, old_margin, new_margin, n, rows, from, flagged_before, flagged_after,
  rate_before, rate_after, exact, worst, applied }` and, when some
  version's scores tie at the cut so that `rate_after` is not the
  requested rate, a `note` naming those versions with the rate each
  reached. `last: "own"` tunes every
  version over its own period — the window it trains on (`window_minutes`
  back for a forest, `window_size` points for timevector, the ring for the
  autoencoder) — so the short-term margin answers for the last three hours
  and the seasonal one for the last ninety days; the report's `window` is
  then the widest of them. On a count clock `last` is a number of points.
  The response also carries the legacy `adjusted_margins` and
  `max_anomaly_scores` maps. 400 on
  a rate outside `[0, 1]`.
- `POST /api/analyze` (members) — the body is a file (the import route's
  `format`, `time`, `tz`, `calendar`, `clock` apply; `name` labels the
  result, default `analysis`). A task directory (`orgs/<org>/tasks/<id>`,
  id = 24 hex chars) receives the input and `params.json`; a child process
  (`anomaly analyze-job <dir>`) opens a store under it, imports the rows
  with the warm-up shrunk to the file, opens every version's window to
  the whole file (`window_minutes`/`window_points` → 0, the file has no
  present), trains at the newest stamp, trains the autoencoder 64-16-64
  with a 1 % pre-filter, fine-tunes every margin to `ANA_TARGET_RATE`
  (1 %) over the file, scans, and writes the result — `task_id`, `name`,
  `format`, `rows`, `imported`, `skipped`, `clock`, `target_rate`, `votes`,
  `anomalies`, `considered`, `model_versions`, `margins`, `time`, `notes`,
  `worst_severity`, `separation`, `reading` — the margins are fitted to
  the file, so `anomalies` is ~1 % of it whatever it holds; `separation`
  is the range guard's `|z|` of the worst row over that of the row at
  twice the cut (a linear magnitude — a forest's decision function
  saturates and the autoencoder's error is heavy-tailed, so their ratios
  say nothing; −1 when the guard gave no verdict) and `reading` says in
  one sentence whether the flagged rows stand apart from the file
  (`separation ≥ ANA_STANDOUT`, 3) or are its tail —
  `points[] { index, timestamp, score, severity, votes, versions[], contributions[]
  { feature, share, value, expected }, values }` — as
  `<safe name>-<id>.json` into the organisation's folder, then
  `status.json` (`state: queued → running → done | failed`, with the
  numbers above, `file`, `size`, or `message`). `?votes=N` (default 1)
  keeps a point only when N or more versions flagged it. The handler
  waits `?wait=` seconds (default 10, max 60, polling every 100 ms with
  the service lock released) and answers as `GET /api/org/tasks/<id>`
  would: 200 `status: success` with the numbers, `file { name, size,
  modified, url, download_url, expires }`, `inline` and — when
  `anomalies ≤ ANA_INLINE_MAX` (10 000) — `points` and `time` read from
  the result file; 202 `status: pending` while queued or running; a
  failed task is 400 from the analyze call and 200 `status: error,
  message` from the task route. A child that dies without a final status
  is marked `failed` with its exit code and stderr tail. Fewer than ten
  parsed rows is a failure. The request body cap is 64 MiB.
- `GET /api/org/tasks` (members) — the organisation's tasks, newest first,
  each the status record plus `task_id`; `DELETE /api/org/tasks/<id>`
  (admin). A malformed id is 400, an unknown one 404.
- `GET /api/org/files` (members) — the organisation's folder,
  `orgs/<org>/files`: `files[] { name, size, modified, url }`, sorted by
  name. `GET /api/org/files/<name>` — the file, `Content-Disposition:
  attachment`, `Cache-Control: private, no-store`, content type by
  extension (`.json`, `.csv`, `.txt`, else octet-stream). With `?org=&exp=&sig=`
  the request is anonymous and the signature decides: `sig` =
  hex HMAC-SHA256(secret, `org\nname\nexp`), the secret being 32 random
  bytes the store writes once to `orgs/link.secret`; compared in constant
  time; 403 "This link is not valid, or has expired." on any mismatch or
  `exp < now`. `POST /api/org/files/<name>/link?ttl=` (members) mints such
  a link (`download_url`, `expires`; ttl default 604 800 s, max
  2 592 000 s). `DELETE /api/org/files/<name>` (admin). Names match
  `[A-Za-z0-9._-]{1,128}` without a leading dot (400 otherwise); the
  result file's stem is the task's name with every other character mapped
  to `_`.
- concurrency: `anomaly serve` runs four worker threads behind one service
  mutex taken in an `http_app_use` middleware — handlers still run one at
  a time (the GPU singleton, the RNG and the authz tables are global), but
  the analyze handler releases the lock while it sleeps between polls, so
  a waiting analysis never delays live traffic. The mutex is released on a
  handler panic too (the recover sits inside the middleware).
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
anomaly train-ae <model> [--hidden 64,32,64] [--contamination C]
anomaly calibrate <model> [--last S|all] [--from T] [--to T]   # alert rates vs margins
anomaly finetune  <model> [--rate R] [--last S|all] [--dry-run]  # write margins for a rate
anomaly reset   <model> [--store DIR]
anomaly rm      <model> [--store DIR]
anomaly ls      [--store DIR]                          # list models
anomaly info    <model> [--store DIR]                  # dump metadata
anomaly serve   [--addr HOST:PORT] [--store DIR]       # run the HTTP service (M5)
anomaly analyze-job <task-dir>                         # internal: one /api/analyze task, spawned by serve
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
- `model_finetune`: for each version, the margin that flags a target share of
  a recent window (§5.5) — the reference's "worst point just inside the band,
  +5 % buffer" was replaced once a real feed showed it tracks one outlier.
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

- **Timestamp encoding.** RESOLVED (M1): raw calendar fields
  (`hour/day/month/weekday`, Python weekday convention), matching the
  reference. Cyclical sin/cos remains a possible later refinement.
- **`contamination = auto`.** RESOLVED (M2): pinned to the sklearn
  convention — `offset_ = -0.5` for `auto`, else the 100·c percentile
  (numpy 'linear' interpolation) of the training set's score_samples;
  `decision_function = -iforest_score - offset_`. Validated against
  scikit-learn on identical data (agreement within ~0.01).
- **Window filtering for versions (M5).** RESOLVED: every mutating entry
  point has an `_at` variant taking `now` in unix seconds; the plain
  variants read the wall clock. Window cutoffs and stamped timestamps are
  fully injectable in tests.
- **Storage backend abstraction.** File backend shipped; the `store_*`
  surface (exists/list/save/load meta + forest, append/write/load points,
  delete) is the interface a Redis/`swarm` backend would re-implement.
  Still open: making `Model` carry the backend as a value rather than
  calling `store_*` directly.
