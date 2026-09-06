# anomaly — streaming anomaly detection, pure NURL

Dynamic, automatically-trainable anomaly-detection **service** over
Isolation Forests. Where the [`iforest`](../iforest) package is the kernel
(numeric matrix in, scores out), `anomaly` is everything around it: named
models that are **created on first use**, ingest one JSON point at a time,
and **train themselves** once enough history has accumulated — no offline
training step, no labels.

```
$ anomaly detect boiler temp=78.2 pressure=1.4 state=heating
{"status":"collecting","min_data_points":50,"data_points":1}
              ⋮            (50 points later the model has trained itself)
$ anomaly detect boiler temp=78.4 pressure=1.4 state=heating
{"status":"success","anomaly":false,"score":-0.012,"versions":{...},"data_points":73}
$ anomaly detect boiler temp=712 pressure=9.9 state=fault
{"status":"success","anomaly":true,"score":-0.31,"versions":{...},"data_points":74}
```

It is a library, a CLI, an HTTP/JSON service with a dashboard, and — for a
language model working on the same data — an [MCP endpoint](#mcp-the-service-for-an-agent)
at `/mcp` that exposes the whole API as tools, under the signed-in user's own
rights.

## Three versions beyond the plain forests

- **range_guard — the univariate check.** A forest scores a point as a
  whole: an air temperature of 95 °C among eleven normal readings is one
  coordinate in a twelve-dimensional space, and the forests may not blink.
  The guard looks at each feature alone — its decision value is
  `−max|z|` over the standardised features, so its margin *is* the sigma
  count of the alert line (4 by default, tunable and calibratable like any
  other), and the verdict names the feature that tripped it. No forest, no
  window: the scaler every retrain refits is all it needs, so it costs
  nothing to keep and nothing to re-enable. A model from before it existed
  gains it at its next retrain.
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
  (pre-filter contamination 10 % unless given), then an MLP autoencoder
  ([`mlp`](../mlp) package: Adam, early stopping, deterministic restarts)
  learns to reconstruct the normal rows; the detection threshold is the
  95th percentile of the training reconstruction errors. It catches what
  marginals hide — a pressure/flow pair each in range but jointly
  impossible. Reported as the `autoencoder` version with the standard
  decision_function orientation (`threshold − mse`; negative ⇒ anomaly).

  **This is the only version that judges the features jointly.** An
  isolation forest splits one axis at a time over a tree capped at
  ~log2(max_samples) levels, so what it scores is how extreme a point is on
  some *single* feature; adding `hour_sin`/`hour_cos` to the input does not
  teach it "no motion at 03:00 is normal, no motion at 15:00 is not". The
  autoencoder does exactly that, and its per-feature reconstruction error
  says *which* relationship broke — see **Why a point is an anomaly** below.

## What a model does

- **Heterogeneous features, encoded automatically.** Numbers pass through;
  strings become deterministic one-hot categoricals (categories kept
  sorted); ISO-8601 strings expand to `hour/day/month/weekday` calendar
  features (Monday = 0 … Sunday = 6). Column types are detected on
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
  change the cadence. Retraining keeps the margins. The autoencoder is
  left alone unless `schedule.autoencoder` is true, in which case it is
  retrained with the forests, with the layer sizes and pre-filter of its
  last manual training.
- **Multiple time-window versions.** Each model trains one forest per
  enabled version — `short_term` (180 min), `daily` (24 h), `weekly`,
  `seasonal` (90 d) and `timevector` (last 100 points) — and the forestless
  `range_guard` beside them, so the same stream is judged against several
  horizons at once. A point is anomalous if
  **any** version flags it; the reported `score` and `severity` are those
  of the most severe version (by severity, the unit-free measure below —
  not by raw score, which is on a different scale per version).
- **Isolation-forest decision conventions.** `score` is `decision_function`:
  `-iforest_score − offset`, `offset = −0.5` for `contamination = "auto"`
  (else the 100·c percentile of training scores). A version flags a point
  when `score ≤ −decision_margin`; margins are read from live metadata, so
  tuning applies without a retrain. Every verdict also carries
  `severity = −score / margin` — 1.0 is exactly the alert line, 2.0 twice
  as far past it, negative is comfortably normal — the one number that
  means the same thing in every version.
- **Calibration and fine-tuning.** `model_calibrate` scores a window of the
  stored ring (the last 24 h by default) through the live verdict path and
  reports, per version, what the current margin flags and which margin
  would flag any given share. `model_finetune` writes the margin for one
  target alert rate (1 % by default). See **How many alerts** below.
- **A nickname.** `alias` is a display name the dashboard shows in place of
  the model's own name, which is often whatever created it. It is ordinary
  editable metadata (`{"alias": "boiler room"}`), never reaches a file path or
  the feature order, and may be cleared back to empty.
- **Persistence.** `metadata.json` (types, categories, feature order,
  scaler, schedule, version configs) + one validated binary forest blob per
  version, written atomically. Corrupt or truncated files load as errors,
  never undefined behaviour. Models survive restarts.

Scores were validated against scikit-learn's `IsolationForest` on identical
deterministic data: `decision_function` values match within ~0.01 across
normal and outlier points. A fixed seed (42) makes forests — and therefore
scores — byte-identical across platforms and runs.

## How many alerts: margins, calibration, fine-tune

The decision rule is one line: a version flags a point when
`score ≤ −decision_margin`, and the model reports an anomaly when **any**
enabled version flags. So the margin is the alert line, and there is
exactly one direction to move it:

| you want | move |
| --- | --- |
| fewer alerts, only the extreme points | **raise** the margin |
| more alerts | **lower** it (0 flags anything the model finds even slightly unusual) |

`contamination` moves the forest's zero line instead (raise → more alerts)
but only at the next retrain, so day-to-day tuning is the margin. The
autoencoder's margin is relative to its learned threshold — flag when
`error ≥ threshold × (1 + margin)` — but reads the same way: raise for fewer.

What a margin *means* in alerts per day is a property of the data, not of
the number, so the service answers that question directly:

```
$ anomaly calibrate boiler                      # last 24 h; --last 604800, --last all
window: 1 441 of 15 500 stored points; any version flags 883 (61.3%)
version       margin    flagged        worst     margin for 0.1% / 1% / 5% / 10%
short_term    0.06  0 (0%)  -0.05485  0.0548514 / 0.0548514 / 0.0536471 / 0.0536471
daily         0.06  0 (0%)  -0.03866  0.0386 / 0.0382 / 0.0375 / 0.037
autoencoder   0  883 (61.3%)  -6.242  6.24 / 6.06 / 5.76 / 5.64
```

`GET /models/dynamic/<m>/calibration?last=86400` is the same report as JSON:
per version the current margin, how many of the window it flags, the margin
for each standard rate (`margin_for_rate`), and a (rate, margin) `curve` a
dashboard can read a live estimate off. Read-only; ~1 ms per stored row.

A flagged row that was nothing — the sensor was being cleaned — can be
told so: `POST /models/dynamic/<m>/labels {"index": 411, "label":
"false_positive", "note": "cleaning"}` (`confirmed` for the real thing,
`none` to withdraw). The label rides on the row through the scan, and
calibration and fine-tune leave labelled false positives out of the rows a
margin is fitted on (`window.excluded` says how many), so the margin stops
paying for known noise. Labels are keyed by the point's lifetime sequence
number, so they survive ring eviction and never land on a row that took a
shifted slot; they change no verdict, so nothing is rescored.

Fine-tune is calibration plus a write: pick the share of the window you are
willing to alert on and every enabled version gets the margin that flags
that share — rounded to the fewest significant digits that keep the count,
so a margin reads `0.13`, not `0.12994712`. When the scores tie at the cut
(a stuck sensor scores whole days identically) no margin flags exactly that
share; the nearer edge of the run is taken and the response says so
(`exact: false`, a `note` with the rate reached), the same way the
calibration's `margin_for_rate` reports `requested_rate` next to
`achieved_rate`:

```
$ anomaly finetune boiler --rate 0.01 --dry-run        # preview, nothing written
$ anomaly finetune boiler --rate 0.01                  # write
$ curl -X POST localhost:8811/api/dynamic/boiler/finetune \
       -d '{"rate": 0.01, "last": 86400, "dry_run": true, "versions": ["daily"]}'
```

The window is counted back from the newest stored point, not the clock, so
a feed that stopped still calibrates on its last day; `last: "all"` is the
whole ring. `last: "own"` (`--last own`) gives every version its own
window — the period it trains on: `short_term` tunes on the last 3 h,
`daily` on 24 h, `weekly` on 7 d, `seasonal` on 90 d, `timevector` on its
window of points — so each margin answers for the horizon its forest looks
at. The dashboard's window picker offers exactly these periods. Ties in the
data can make the count land above the target — the report says what it
actually flagged, before and after.

On a model without timestamps (a *count clock*, see below) every window is a
number of points: `last: 1440` is the newest 1,440 points, `--last 100` the
newest hundred.

The table above is also the drift detector: an autoencoder trained once on
a week in June and never again will, by September, flag most of every day
(`883 (61.3%)` at margin 0 is exactly that). The cure is a retrain, not a
margin — tick `schedule.autoencoder` or train it again by hand.

## Why a point is an anomaly

A verdict says *that* a point is anomalous and which versions agreed. For the
autoencoder it can also say **why**: its reconstruction error is per-feature,
and a feature's share of the total is the amount by which that feature failed
to be predictable from all the others. So the top contributors name the
*relationship* that broke, not merely the largest number in the record.

```
$ curl 'localhost:8811/models/dynamic/boiler/anomalies?last=86400&only=anomalies'
{"points":[{"index":6771,"timestamp":1788496324,"score":-0.121,"anomaly":true,
  "versions":["weekly","autoencoder"],
  "contributions":[{"feature":"flow","share":0.41,"value":5.0,"expected":3.02},
                   {"feature":"pressure","share":0.19,"value":2.1,"expected":2.31},
                   {"feature":"hour_sin","share":0.14,"value":0.5,"expected":0.44}]}], ...}
```

Each contributor carries the value the point had and the one the autoencoder
reconstructed for it from the other features — the sentence "flow was 5.0
where 3.0 was expected" is in the response, not left for the reader to infer.

A per-feature z-score from the column mean would not do: it can only ever
point at the value that was extreme, which is the question the forests were
already answering.

## Scanning stored history

`GET /models/dynamic/<m>/anomalies` re-scores the stored ring in one request —
one model load for the whole window instead of one per point — and caches the
verdicts on disk (`scores.bin`).

The cache is stamped with the model's **scoring epoch**, a counter bumped by
anything that can change a verdict: a retrain, a new autoencoder, a margin
edit, a version toggled on or off, a metadata patch, a reset. An entry with an
older epoch is stale by construction, so there is no per-entry invalidation
rule to get wrong. Cache rows are keyed on the lifetime point counter rather
than the ring index, so ring eviction shifts nothing.

On a 7 271-point model with five forests and an autoencoder: 329 s of
`/detect_only` round trips before (45 ms each, which is why the dashboard used
to cap the scan at 500 points), **14 s cold, 0.1 s warm** after. The response
reports `cache: { hits, misses, epoch }` so the dashboard can show which it
got. `?refresh=1` recomputes anyway — the escape hatch for verifying the cache,
never needed for correctness.

## Importing a file of history

A model does not have to be grown from a stream. `POST
/models/dynamic/<m>/import` — or the file picker on `/modeltrainer.html` —
takes a file that already holds the history and turns it into the same
records the ingest path takes.

| format | shape |
| --- | --- |
| `csv` | a header row naming the columns, one row per point. Delimiter guessed from `,` `;` tab; quoted cells honoured. Cells that parse as numbers become numbers, everything else stays text |
| `json` | an array of objects, or an object with the array under `data`, `points` or `rows` |
| `jsonl` | one object per line — what this service's own `/data` route emits, so a model can be moved by exporting and importing it |

`?format=auto` (the default) sniffs: a body starting with `[` is a JSON
array, one starting with `{` is JSONL if later lines also start objects,
anything else is CSV.

Two things it does that a replay through `/detect` would not:

- **Points keep the `timestamp` the file gives them.** History that all
  lands at "now" is not history — every time window would see one instant,
  and `seasonal` would be as blind as `short_term`. Imported points are
  merged into the ring in time order, so a file of last year's data lands
  *before* this morning's points rather than after them.
- **The log is written once and the model trains once**, at the end. Replaying
  ten thousand points through the streaming path would retrain two hundred
  times and rewrite the log ten thousand times.

A row that cannot be read does not fail the file: it is counted, and the
first few are named by line. A file bigger than the ring is a file whose
*tail* the model keeps. `-`, `--`, `NA`, `N/A`, `NaN`, `null` and `None`
are missing values, not text.

### Finding the time in a file

A file rarely calls its clock `timestamp`. The importer reads the columns
before a row lands and proposes where the time is:

- a **column** whose values parse as a stamp under any name (`ajanhetki`,
  `ts`, `created`…): ISO 8601 / RFC 3339, the Postgres and MySQL
  `TIMESTAMP` / `TIMESTAMPTZ` forms (`2026-08-29 00:10:00+03`), compact
  `20260829T001000`, Unix seconds / milliseconds / microseconds /
  nanoseconds, or a bare date;
- **parts** — year / month / day plus a clock or hour / minute / second,
  under English or Finnish names (`Vuosi`, `Kuukausi`, `Päivä`, `Aika`,
  `tunti`, `min`…), the way an FMI weather export is laid out;
- **none** — nothing in the file reads as a time.

`POST /models/dynamic/<m>/import?inspect=1` returns that proposal with its
confidence and a sample of the first row read (`2026-08-29T00:00:00+03:00`)
and creates nothing; the trainer page shows it and lets you confirm, pick
another column or set of parts, choose the zone naive stamps are read in
(`tz=local|utc|+03:00`), or import with no time at all. The import call
takes the plan back (`time=<json>`, `{"mode":"auto"}` is the proposal) and
drops the columns it consumed, so a year never becomes a feature.
`calendar=1` keeps an ISO `time` column so hour / weekday / month become
features of the model.

### Data without timestamps: the count clock

Points that carry no time are not given one. A model born from unstamped
rows runs on a **count clock** (`"clock": "count"` in its metadata): the
n-th point is simply #n, every window in the package is a number of points
— a `window_minutes: 1440` forest is the last 1,440 points, `last=100` the
newest hundred — and the dashboards label points by their ordinal instead
of a date. Nothing time-of-day shaped is derived. The clock is settled by
the first points and can only change while the model is empty
(`{"clock": "time"}` through the metadata, or `?clock=` on the first
import); rows arriving later conform to it, and the import says so in
`notes` when it had to ignore stamps or invent them.

Creating a model is a structural act, so importing is an admin's — and the
model it creates belongs to the **organization**, exactly like one grown from
a stream. There is no third kind of model.

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
forces the CPU backend on a CUDA machine. A CUDA context is current only
on the thread that opened it, so every accelerated path binds the calling
thread first — `anomaly serve` scores and trains from a worker pool, and
which thread a request lands on must not decide which engine runs.

A scan, calibration or fine-tune over stored rows (the anomalies route,
`model_scan_at`, `model_calibrate`) encodes the rows once — each ring row
in range parsed, projected and scaled a single time — and takes every
forest's decisions from the bulk scorer over the whole range, so the
per-row verdict only reads: 10 000 rows calibrate in 0.7 s accelerated,
2.6 s on the CPU.

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

## Configuration

Everything the service can be told layers in one fixed order:

```
command-line flag  >  environment variable  >  config file  >  built-in default
```

The file is the persistent baseline a deployment writes once; the environment
is what a container or a unit file overrides for one run; a flag is what a
person types to override both.

The file is TOML, looked for in this order — `--config FILE` or
`$ANOMALY_CONFIG`, then `<store>/anomaly.toml`, then
`/etc/anomaly/anomaly.toml`. An `anomaly.toml.example` ships beside this
README.

```toml
[auth]
enabled     = true
issuer      = "https://login.example.com/<tenant>/v2.0"
client_id   = "<application (client) id>"
audience    = "https://<your-host>/mcp"   # optional; default api://<client id>. See "An agent's client" below
open_ingest = true

[service]
addr       = "0.0.0.0:8811"
webroot    = "/usr/share/anomaly/static"
public_url = "https://anomaly.example.com"   # only behind a proxy that rewrites Host
```

| Key | Environment | Flag |
| --- | --- | --- |
| `auth.mode` | `ANOMALY_MODE` | — |
| `auth.owner_tenant` | `ANOMALY_OIDC_OWNER_TENANT` | — |
| `auth.issuer` | `ANOMALY_OIDC_ISSUER` | — |
| `auth.client_id` | `ANOMALY_OIDC_CLIENT_ID` | — |
| `auth.audience` | `ANOMALY_OIDC_AUDIENCE` | — |
| `auth.multi_tenant` | `ANOMALY_OIDC_MULTI_TENANT` | — |
| `auth.allowed_tenants` | `ANOMALY_OIDC_ALLOWED_TENANTS` | — |
| `auth.open_ingest` | `ANOMALY_OPEN_INGEST` | — |
| `service.addr` | `ANOMALY_ADDR` | `--addr` |
| `service.webroot` | `ANOMALY_WEBROOT` | `--webroot` |
| `service.public_url` | — | — |
| — | `ANOMALY_HOME` | `--store` |
| — | `ANOMALY_CONFIG` | `--config` |

The store directory is deliberately **not** settable in the file: the file is
looked for inside the store, so a `store` key would be a file relocating the
directory it was just found in.

A file that does not exist is fine — most deployments have none. A file that
exists and does not parse **stops the service** with exit 2, because coming up
unconfigured because a config file was quietly ignored is the failure nobody
can see.

## Two modes

```toml
[auth]
mode = "simple"   # or "oidc"
```

**simple** — no sign-in at all. Anyone who opens the page sees every model,
and what the API collects lands in one `public` organization. This is what the
service was before sign-in existed, kept as a mode rather than as a fallback
so a deployment that wants it says so. It is the default.

**oidc** — signed in and multi-tenant. A model belongs to an **organization**,
and nothing is created or collected without a credential naming one.

## Signing in, organizations, and who owns what

In `oidc` mode the service verifies OIDC bearer tokens with the
[`oauth`](../oauth) package (its own JWKS fetch, its own signature and claim
checks — nothing in that chain is C). Four things follow.

**An organization is an OIDC tenant.** The `tid` claim (or, for a provider
publishing none, the issuer) selects one SQLite database under
`<store>/orgs/<org>.db`. The org is *implicit in the file*, so no query in
`authz.nu` carries an org column and none can forget one. An org id that is
not a plain GUID is replaced by a digest of itself before it becomes a
filename.

**A model belongs to the organization, never to a person.** Everyone in it
sees the same models — a colleague leaving must not take a production model
with them — and the *role* decides what may be done to one. The model store is
a single flat directory shared by every organization, so membership is the
whole scope: a model your organization has not claimed is invisible to you,
admin or not.

**Two roles for people.**

| | viewer | admin |
| --- | --- | --- |
| the organization's models, their data, the charts | ✓ | ✓ |
| create, train, finetune, reset, delete, edit **scratch models** named `llm_…` | ✓ | ✓ |
| train, finetune, reset, delete, edit any other model | | ✓ |
| API keys, users and roles | | ✓ |

The `llm_` namespace is the one place a viewer may write: a model named
`llm_<anything>` is a scratch model, which every member — in the dashboard,
over the API or through an agent on `/mcp` — may fork from a production
model's history, tune, and delete, without ever being able to touch the
production model itself. The rule lives in the authorization gate
(`az_is_scratch_model`), so every surface agrees on it.

Sending data is a third thing, and it is not on this axis at all: it is done
by the organization's **key**, not by a person. See *API keys* below.

The first subject to authenticate from an organization becomes its admin —
there is nobody else who could have granted it — and the last admin cannot be
demoted.

**Nothing is collected without a credential.** `POST /detect` from an
unauthenticated caller is refused and creates nothing: without a credential
naming an organization there is nothing a point could belong to, and a model
made from one would be owned by nobody. `auth.open_ingest` is the migration
window for producers not yet carrying a key — and even then those points land
in the `public` organization rather than conjuring an ownerless model.

### The owner tenant

```toml
owner_tenant = "<tenant-id>"
```

One organization administers the *service*, from `/admin.html`:

- **Which organizations may use it.** An organization that signs in and has
  not been approved is recorded as **pending** and refused. Approving,
  blocking and un-approving are done from the dashboard; `allowed_tenants` in
  the config only ever *adds*, so a decision made in the dashboard is never
  undone by a restart.
- **Any organization's members.** Including the repair an organization cannot
  do for itself: when its last admin has left, promoting somebody is an
  admin's act and there is no admin left. From here, that account can be
  deleted and another promoted.

It is set in the configuration file and nowhere else, and it is always allowed
to sign in. A tenant that could grant itself this from the dashboard would not
be an anchor, and one that could be locked out would leave nobody able to
unlock anything.

### The right to be forgotten

`DELETE /api/me`, or the button on `/admin.html`.

The person's row goes, and with it the personal identifier attached to
anything they made. What stays is what belongs to the **organization**: its
models, and the API keys that feed them — a colleague leaving must not stop
the data arriving, so a key records the role it was issued with rather than
reading it from a creator who may no longer exist.

Unless they were the last member. An organization with nobody in it has nobody
it could belong to, so it goes: its models are deleted from the store, then its
database. In that order — a crash between the two leaves models nobody claims,
which an admin can adopt, while the reverse leaves a database pointing at
models that are gone.

### Setting up the identity provider

Any OIDC provider that publishes discovery and a JWKS will do. The dashboard
is a **public client** doing authorization-code with PKCE, so there is no
secret to store anywhere. Register:

| | |
| --- | --- |
| application type | SPA / public client, PKCE, **no** client secret |
| redirect URIs | `https://<your-host>/oauth/callback` and `http://localhost:8811/oauth/callback` |
| scopes | `openid profile email`, plus one scope for this API |
| claims | `email` and `preferred_username` in the ID and access tokens |
| for agents on `/mcp` | the MCP client's redirect URI as a **public client**, and `https://<your-host>/mcp` as an identifier of this API — see [An agent's client](#an-agents-client) |

#### One organization, or any

A **single-tenant** application has one issuer, and a token either carries it
or is refused.

A **multi-tenant** one has no single issuer: every organization signs its
users' tokens with its own, and the provider says so — Entra's discovery
document at the multi-tenant authority publishes the literal string

```
"issuer": "https://login.microsoftonline.com/{tenantid}/v2.0"
```

which is a template, not a URL. There is nothing to pin. Set
`auth.multi_tenant = true` and the service checks what the provider documents
instead: a token's `iss` must be that template with the token's own `tid`
substituted. Both claims sit inside the same signature, so a token cannot be
moved between tenants.

For Entra, `auth.issuer` must then be
`https://login.microsoftonline.com/organizations/v2.0` and the registration's
sign-in audience must be `AzureADMultipleOrgs`. Register single-tenant and sign
in with an outside account and you get

```
AADSTS50020: User account '…' from identity provider '…' does not exist in
tenant '…' and cannot access the application '…' in that tenant.
```

which names the mismatch exactly.

#### An agent's client

An MCP client that signs the person in — Claude, or any client that follows
the MCP authorization spec — is an OAuth client of its own, and it differs
from the dashboard in two ways the registration has to allow for.

**Its redirect URI is not on your host.** The client names its own callback
(Claude's is `https://claude.ai/api/mcp/auth_callback`, and
`https://claude.com/api/mcp/auth_callback` alongside it), and it exchanges
the code from its own servers, without a secret: authorization-code with
PKCE. Register that URI as a **public client** — in Entra, the *Mobile and
desktop applications* platform. The other two platforms refuse exactly this
exchange: *Web* demands a client secret, and *Single-page application*
demands a browser's `Origin` header on the token request.

**It names the resource it wants a token for.** The client reads the
`resource` this service publishes at `/.well-known/oauth-protected-resource/mcp`
— `https://<your-host>/mcp` — and sends it with every authorization request
([RFC 8707](https://www.rfc-editor.org/rfc/rfc8707)). Entra checks that the
scope requested belongs to that resource, and `api://<client id>` is a
different resource, so the sign-in ends in

```
AADSTS9010010: The resource parameter provided in the request doesn't match
with the requested scopes.
```

The fix is one name for one thing: add `https://<your-host>/mcp` as a second
*Application ID URI* of the registration (Entra accepts an `https://` URI
only on a domain verified in your tenant) and set `auth.audience` to it. The
service then advertises `https://<your-host>/mcp/access_as_user` as the
scope, resource and scope agree, and the dashboard keeps working — it
requests the same permission under the new name, and the access token's
`aud` is the client id either way, which is the second spelling the service
accepts.

Give the MCP client the same `client_id` as the dashboard and no secret.

#### Azure AD (Entra ID), with `az`

`az ad app create` has no flags for SPA redirect URIs, for exposing an API, or
for the token version, so those three are a Graph PATCH:

```bash
APPID=$(az ad app create --display-name anomaly \
          --sign-in-audience AzureADMultipleOrgs --query appId -o tsv)
          # ...or AzureADMyOrg for a single-organization deployment
OID=$(az ad app show --id "$APPID" --query id -o tsv)
SCOPEID=$(uuidgen)

# 1. SPA redirect URIs, the API this app exposes, and v2 access tokens.
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OID" \
  --headers "Content-Type=application/json" --body "$(cat <<JSON
{
  "spa": { "redirectUris": [
      "https://<your-host>/oauth/callback",
      "http://localhost:8811/oauth/callback" ] },
  "publicClient": { "redirectUris": [
      "https://claude.ai/api/mcp/auth_callback",
      "https://claude.com/api/mcp/auth_callback" ] },
  "identifierUris": [ "api://$APPID", "https://<your-host>/mcp" ],
  "api": {
    "requestedAccessTokenVersion": 2,
    "oauth2PermissionScopes": [ {
      "id": "$SCOPEID", "value": "access_as_user", "type": "User",
      "isEnabled": true,
      "adminConsentDisplayName": "Access anomaly as the signed-in user",
      "adminConsentDescription": "Call the anomaly API as the signed-in user.",
      "userConsentDisplayName": "Access anomaly on your behalf",
      "userConsentDescription": "Call the anomaly API as you." } ] },
  "optionalClaims": {
    "idToken":     [ {"name": "email"}, {"name": "preferred_username"} ],
    "accessToken": [ {"name": "email"}, {"name": "preferred_username"} ],
    "saml2Token":  [] }
}
JSON
)"

# 2. Pre-authorize the app against its own scope — the scope has to exist
#    first, which is why this is a second call. Without it the first sign-in
#    stops at a consent prompt for a permission the app grants itself.
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OID" \
  --headers "Content-Type=application/json" \
  --body "{\"api\": {\"requestedAccessTokenVersion\": 2,
    \"oauth2PermissionScopes\": [{\"id\": \"$SCOPEID\", \"value\": \"access_as_user\",
      \"type\": \"User\", \"isEnabled\": true,
      \"adminConsentDisplayName\": \"Access anomaly as the signed-in user\",
      \"adminConsentDescription\": \"Call the anomaly API as the signed-in user.\",
      \"userConsentDisplayName\": \"Access anomaly on your behalf\",
      \"userConsentDescription\": \"Call the anomaly API as you.\"}],
    \"preAuthorizedApplications\": [{\"appId\": \"$APPID\",
      \"delegatedPermissionIds\": [\"$SCOPEID\"]}]}}"

# 3. A service principal is what makes the app signable-into in this tenant.
az ad sp create --id "$APPID"
```

Two steps there bite:

- **`requestedAccessTokenVersion: 2`.** A v1 access token is signed by
  `sts.windows.net`, not by the issuer discovery advertises, so it fails the
  issuer check for no visible reason.
- **`preAuthorizedApplications` needs the scope to already exist**, hence two
  PATCHes. A single one fails with *"has a Permission Id that cannot be found
  in the AppPermissions sets"*.
- **`https://<your-host>/mcp` must be on a domain your tenant has verified**,
  or the PATCH is refused. Without it an MCP client cannot sign in at all
  (`AADSTS9010010`, above); the dashboard does not need it. Set
  `auth.audience = "https://<your-host>/mcp"` to match.

Sanity-check the registration without a browser by building the authorize URL
the dashboard would and fetching it: a real sign-in page means the client id,
redirect URI, scope and PKCE all check out; an `AADSTS…` code in the body names
what does not.

### Rolling it out without losing data

1. **Deploy in `simple` mode.** Nothing changes.
2. **Switch to `oidc`** with the issuer, client id and owner tenant. Sign in —
   you are the first subject, so you are your organization's admin. Models
   that predate this are unclaimed; adopt them from `/admin.html`.
3. **Issue an API key** for each producer that cannot sign in, and switch them
   over. `auth.open_ingest = true` keeps them writing in the meantime, into the
   `public` organization.
4. **Close the window.** `open_ingest = false` once every producer carries a
   key.

### API keys

For machines that cannot do an interactive sign-in. A key authenticates as the
**organization** and carries a capability of its own, so it keeps working when
the person who issued it is forgotten.

An **ingest** key — the default, and what a producer wants — may put data in:
send points, import a file, and bring a model into being by doing either. The
first point for a new sensor defines a new model, and requiring an
administrator's credential to report a reading would be the opposite of least
privilege. It may do nothing else: not retrain, not reset, not delete what it
feeds, not edit metadata, not learn that another key exists.

An **admin** key can do everything an administrator can. Only issue one when
something genuinely has to manage the organization unattended.

There is no viewer key: a machine that only reads is pointless, and a person
who reads signs in. A key that ever carried the role is read as ingest.

```
$ curl -H 'Authorization: Bearer anok_<id>_<secret>' https://…/models/dynamic
$ curl -H 'X-API-Key: anok_<id>_<secret>'            https://…/detect/boiler -d '{…}'
```

Keys are stored as a SHA-256 of the secret: the plaintext exists once, in the
response that creates it. An admin can revoke anyone's; a viewer only their
own. Revocation takes effect on the next request.

### The dashboard

`static/auth.js` does the authorization-code flow with PKCE in the browser and
wraps `fetch` once, so each page calls the API exactly as it did before
authentication existed — what a page must do is `await Auth.ready()` before its
first request. `/admin.html` is where an organization's keys, users and models
are managed, and where the owner tenant approves organizations.

## MCP: the service for an agent

`POST /mcp` is the same service for a language model — [Model Context
Protocol](https://modelcontextprotocol.io) over Streamable HTTP, built on the
stdlib's `mcp_server` / `mcp_http` / `mcp_auth`. Every tool is a thin, named
view of an API route, and every call runs **as the signed-in user, inside
their organization, with their role**: the agent can do exactly what the
person driving it could do in the dashboard, and nothing more.

```
$ claude mcp add --transport http anomaly https://anomaly.example.com/mcp
```

In `oidc` mode the endpoint answers an unauthenticated call with the standard
challenge — `401`, `WWW-Authenticate: Bearer resource_metadata="…/.well-known/oauth-protected-resource/mcp"` —
and that document names the issuer and the scope, so an MCP client that
speaks OAuth signs the person in by itself against the same identity provider
the dashboard uses — the same `client_id`, with the client's own redirect
URI and this service's `/mcp` URL registered on the app as
[An agent's client](#an-agents-client) describes. A machine agent uses an
API key instead:
`--header "X-API-Key: anok_…"`. In `simple` mode there is no sign-in and
every call is an administrator's, as everywhere else.

**What a role sees.** `tools/list` shows only the tools the caller may use; a
tool the caller may not see is *unknown*, not *forbidden*. When a visible
tool refuses something — a viewer retraining a production model — the reply
says why and what would be allowed instead.

| Tool | Who | What |
| --- | --- | --- |
| `whoami` | every member | organization, role, and what the role allows through these tools |
| `list_models` | every member | every model: columns, points seen, last training, each version's margin |
| `describe_model` | every member | how a model is built, and which fields `edit_model` may change |
| `anomalies` | every member | the newest flagged points of a window with the features blamed; says how many the window held |
| `anomaly_summary` | every member | a window in one screen: counts, rate, per-version counts, worst point, events, timeline, most-blamed features |
| `points`, `point` | every member | the raw stored rows of a window; one row in full by ring index |
| `calibration` | every member | how each margin sits against a window — the numbers to read before `finetune` |
| `score_point` | every member | the verdict for a hypothetical point, without storing it |
| `analyze_data` | every member | a one-off analysis of a file (CSV text or rows), no model kept; large files become a task |
| `list_tasks`, `task`, `list_files` | every member | the organization's background jobs and its folder |
| `fork_model` | every member | a new model trained on a slice of another's history — a window, some columns; `llm_…` is scratch |
| `labels` | every member | what readers have said about a model's rows |
| `label_anomaly` | member on `llm_…`, admin on any | say a flagged row was a `false_positive` (calibration and `finetune` leave it out from then on), `confirmed`, or `none` to withdraw |
| `retrain`, `train_autoencoder`, `finetune`, `edit_model`, `reset_model`, `delete_model` | member on `llm_…`, admin on any | the model's lifecycle; destructive ones need `confirm: true` |
| `ingest_point`, `import_data` | ingest key, admin | send a point / load a file of history — this teaches the model |
| `claim_model`, `org_users`, `set_role`, `org_keys` | admin | ownership, the roster, roles, the key listing |

API keys are deliberately **listed but never created or revoked** through
MCP: a new key's secret exists once, in the response that creates it, and a
conversation with a language model is not where it should land. Use the
dashboard.

Every tool answers in a reader's shape rather than the route's: stamps are
ISO-8601 (or the point's ordinal on a count clock), readings are rounded to
four significant digits, margins are never rounded (a rounded margin is a
different threshold), and a row is `{ index, time, values: {…} }` so a column
named `time` cannot shadow the stamp. A window is `from` / `to` and a span
`last` — seconds or `90s` / `15m` / `24h` / `7d` / `2w`, and `"all"` for every
stored point; `finetune` also takes `"own"` for each version's own training
period. `anomalies` and `anomaly_summary` take `min_votes`: with `2` on a
three-version model, a row one version alone flagged is not counted.
Consecutive anomalous rows are one **event**: every row in `anomalies`
carries its `event` number, both tools count `events_in_window`, and
`anomaly_summary` lists the newest ten events with their span, worst row and
versions, and counts event starts per timeline bucket — so a hundred flagged
rows read as the three bursts they were. The REST route calls them runs
(`runs`, `run`, `group=runs`). A row the person calls nothing is labelled
with `label_anomaly {model, index, label: "false_positive"}`: it shows on the
row in `anomalies`, the summary counts it under `labelled`, and `calibration`
and `finetune` report it under `window.excluded`.

The server's `instructions` tell the agent the things it most often gets
wrong: that `last: "24h"` counts back from the model's newest point, not from
the clock, and that scores run downward and are ranked by `severity`
(−score / margin, 1.0 being the alert line) — the lowest score of one
version is not comparable with another's. A typical session is `list_models` → `anomaly_summary {model,
last:"7d"}` → `anomalies {model, last:"24h"}` → `point {model, index}`;
a hypothesis is tested with `fork_model {source, name:"llm_…", fields:[…]}`
→ `calibration` → `finetune` → `delete_model {confirm:true}`.

Behind a reverse proxy that rewrites `Host`, set `service.public_url` so the
challenge and the metadata document name the origin agents actually reach.

## CLI

```
anomaly detect <model> key=val ...     # ingest one point → verdict JSON
anomaly score  <model> key=val ...     # score only (never ingests/retrains)
anomaly batch  [-f FILE] [-H] [-m M]   # stateless CSV scoring (index⇥score)
anomaly train  <model>                 # force a retrain now
anomaly train-ae <model>               # train the autoencoder version
anomaly calibrate <model> [--last S]   # alert rates vs margins over a window
anomaly finetune <model> [--rate R]    # set every margin from a target rate
               [--last S|all|own] [-n] #   (own: each version its own period;
                                       #    -n / --dry-run previews)
anomaly reset  <model>                 # drop data+forests, keep the name
anomaly rm     <model>                 # delete the model entirely
anomaly ls / info <model>              # list models / dump metadata
anomaly serve  [--addr HOST:PORT]      # run the HTTP/JSON service + dashboard
               [--webroot DIR]
anomaly analyze-job <task-dir>         # (internal) run one /api/analyze task
```

The store defaults to `$ANOMALY_HOME`, else `~/.anomaly`; override per
command with `--store DIR`.

## HTTP service

`anomaly serve` exposes these routes:

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
| `GET /models/dynamic/<m>/anomalies` | re-score the stored ring, cached (see below) |
| `POST /models/dynamic/<m>/claim` | adopt an unclaimed model into your organization |
| `POST /models/dynamic/<m>/import?format=&inspect=&time=&tz=&calendar=&clock=` | import a CSV/JSON/JSONL file of history; `inspect=1` proposes where its time is |
| `POST /api/analyze?wait=&votes=&name=&format=&time=&tz=&calendar=&clock=` | analyse a file sent as the body: train, fine-tune to 1 %, return the anomalies (see below) |
| `GET /api/org/tasks[/<id>]`, `DELETE /api/org/tasks/<id>` | the organization's analyses and their results |
| `GET /api/org/files[/<name>]`, `POST /api/org/files/<name>/link?ttl=`, `DELETE /api/org/files/<name>` | the organization's folder: list, download, pre-authenticated link, delete |
| `DELETE /api/me` | delete your account (right to be forgotten) |
| `GET\|PUT /api/tenants[/<tid>]` | approve organizations (owner tenant) |
| `GET /api/orgs`, `GET\|PUT\|DELETE /api/orgs/<org>/users[/<sub>[/role]]` | administer any organization (owner tenant) |
| `POST /mcp` | the same API as MCP tools for a language model, under the caller's rights (see above) |
| `GET /.well-known/oauth-protected-resource[/mcp]` | where `/mcp` callers get a token (RFC 9728) |
| `GET /api/auth/config` | what a browser needs to start a sign-in (public) |
| `GET /api/me` | the caller's identity, organization and role |
| `GET\|PUT /api/org/users[/<sub>/role]` | the organization's roster (admin) |
| `GET\|POST /api/org/keys`, `DELETE /api/org/keys/<id>` | API keys |
| `POST /models/dynamic/<m>/reset` | drop data + forests, keep the name |
| `DELETE\|GET /delete_model/<m>` | delete entirely |
| `PUT /api/dynamic/<m>/schedule` | `{"below_max_retrain_frequency": .., "at_max_retrain_frequency": ..}` |
| `GET /models/dynamic/<m>/calibration?last=&from=&to=&curve=` | alert rates vs margins over a window of the ring (read-only) |
| `POST\|GET /models/dynamic/<m>/labels` | `{"index": N, "label": "false_positive" \| "confirmed" \| "none", "note": ".."}` — a reader's word on a stored row; the list in force |
| `POST /api/dynamic/<m>/finetune` | set margins from a target alert rate — `{"rate": 0.01, "last": 86400 \| "all" \| "own", "dry_run": false, "versions": [..]}` |
| `POST /train/autoencoder/<m>` | train the autoencoder version — optional `{"hidden": [..], "contamination": x}` |

Model names must match `^[a-zA-Z0-9_]+$`. The router is a plain function
over `HttpRequest` — the test suite drives every route without a socket.

### Analysing a file

`POST /api/analyze` is the import route without the model: send a CSV,
JSON or JSONL file as the body (`format=`, `time=`, `tz=`, `calendar=` and
`clock=` mean what they mean for an import; `name=` labels the result) and
the service trains a throwaway model on it — every forest version over the
whole file, the autoencoder as 64-16-64, every margin fine-tuned to a 1 %
alert rate — scans it and answers with the anomalies:

```
curl --data-binary @week.csv "https://host/api/analyze?name=week%2036&wait=30"
{ "status": "success", "state": "done", "task_id": "…", "task_url": "/api/org/tasks/…",
  "rows": 10080, "anomalies": 143, "target_rate": 0.01, "votes": 1,
  "model_versions": ["short_term", …, "autoencoder"], "margins": { … },
  "file": { "name": "week_36-….json", "size": 61022, "url": "/api/org/files/…",
            "download_url": "/api/org/files/…?org=…&exp=…&sig=…", "expires": … },
  "inline": true,
  "points": [ { "index": 411, "timestamp": …, "score": -0.113, "votes": 4,
                "versions": ["short_term", "daily", "weekly", "seasonal"],
                "contributions": [ { "feature": "rh", "share": 0.6, "value": 47.9, "expected": 48.4 }, … ],
                "values": { …the whole record… } }, … ] }
```

Up to 10 000 points come inline (`inline: true`); the full result — the
same object, points included — is always written to the organization's
folder, and `download_url` is a pre-authenticated link to it: anyone
holding it can fetch the file until `expires` (seven days), no sign-in.
Each version is calibrated to 1 % on its own and a point is an anomaly
when any of them says so, so the union runs above 1 %; `votes=2` keeps
only the points two or more versions agreed on, which lands near it.

The call waits `wait=` seconds for the job (default 10, at most 60). A
job still running after that answers **202** with `state: "queued"` or `"running"`, and
`GET /api/org/tasks/<task_id>` (the `task_url`) gives the very same answer
once it is done — poll it, or come back later: `GET /api/org/tasks` lists
the organization's analyses, newest first, with their state. A job that
fails (nothing parses, fewer than ten rows) answers 400 with the reason
while the call waits, and `state: "failed"` with a `message` from the task
route afterwards. Members (viewer or admin) see their organization's
tasks; admins delete them. Analyses run as a child process
(`anomaly analyze-job`), so the live models, the GPU and the service
itself are never in the job's hands.

### The organization's folder

Every organization has a folder in the store (`orgs/<org>/files`).
`GET /api/org/files` lists it (`name`, `size`, `modified`, `url`), `GET
/api/org/files/<name>` downloads a file — both for members, viewer or
admin. `POST /api/org/files/<name>/link?ttl=<seconds>` mints a
pre-authenticated link (default seven days, at most thirty): the file's
URL with `org`, `exp` and an HMAC signature over the three, keyed by a
secret the store generates once (`orgs/link.secret`). A link opens exactly
that file of that organization until it expires; a tampered or expired one
is a 403. Admins `DELETE` files. Names are `[A-Za-z0-9._-]`, no leading
dot, at most 128 characters.

### Editing the metadata

`PUT /models/dynamic/<m>/metadata` takes the *editable half* of the
metadata. Every key is optional, but at least one must be present, and
every field inside is optional too — what the patch omits keeps its value,
so a checkbox can send one field:

```jsonc
{
  "schedule": { "below_max": 50, "at_max": 1000,
                "autoencoder": false },            // true ⇒ the AE retrains with the forests
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
| `/` · `/modelmanager.html` | list models, train / finetune / reset / delete; per model: toggle versions, edit margins and contamination with a live *flags in window* column from the calibration report, preview and apply a fine-tune for a target alert rate, train the autoencoder, edit the retrain schedule — or, under *Advanced*, the whole editable metadata, as a generated field form or as raw JSON. Every alert-affecting control carries a `?` that says what it means and which way to move it |
| `/modeltrainer.html` | import a CSV/JSON/JSONL file of history — inspect first: the page shows where it found the time (a column, year/month/day parts, or none) and lets you confirm or change it; feed points (`/detect`) one at a time or in bulk; force-train |
| `/visualize.html` | plot any numeric feature of a model's stored points over time |
| `/admin.html` | the organization: users and their roles, API keys, model ownership |
| `/anomalies.html` | scan stored history over a time range: score timeline, a per-version ribbon showing *what* flagged *when*, any feature's own trace for context, and a table naming the features whose relationship broke — with the value each had and the one the autoencoder expected; forest-only flags list the point's most extreme values in σ. Drag across a chart to zoom into a stretch of points, double-click or *reset zoom* to see the whole range; click a point for its stored record and every feature as the model saw it. Filter chips isolate the joint (autoencoder) anomalies from the per-feature (forest) ones |

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

`model_open / model_ingest / model_detect_only / model_scan /
model_ae_contrib / model_point_json / model_force_train / model_reset /
model_delete / model_calibrate / model_finetune / model_finetune_at /
model_train_autoencoder /
model_set_schedule / model_set_margin / model_set_version_enabled /
model_set_version_window / model_apply_meta_patch / model_metadata /
model_free`, plus the layers beneath:
preprocessing + scaler (`prep.nu`), the per-point decision core over
`iforest` (`model.nu`), bulk/batch scoring + training with the GPU path
(`score.nu`), persistence (`store.nu`), batch CSV (`csvdata.nu`) and the
HTTP surface (`service.nu`). Every mutating entry point has an
`_at` variant taking `now` in unix seconds — the injectable clock that
makes window filtering reproducible in tests.

## Design decisions

Each of these is documented where it is implemented; the short form:

1. **Fine-tune sets a rate.** A margin that lands the worst point seen just
   inside the band is a function of one outlier. Here fine-tune is
   calibration plus a write: the margin that flags a chosen share of a
   recent window, in place (no `tune_<name>` clone).
2. **One scaler per model**, fit over the full ring, shared by every
   version — so two versions' scores are on the same footing.
3. **Retraining is keyed on the lifetime point counter**, so it keeps
   working at ring capacity, where a count of stored points stops moving.
4. **`timevector` trains a forest on the last 100 points** through the
   same scaler as every other version.
5. **`/detect_anomalies` self-trains on the file**; there is no separate
   static-model family, and passing `model_name` is a 400 rather than a
   silent switch to a different one.
6. **Points store raw JSON lines** (`data.jsonl`) — raw records are what let
   retrains learn new categories.
7. **The autoencoder's margin is relative, not absolute.** Its threshold is
   the p95 of the training reconstruction errors, often ~5e-4; an absolute
   `decision_margin` of `0.05` against that would need an error ~100× the
   threshold and switch the joint detector off in practice. Here
   `decision_margin` is a fraction of the model's own threshold, so `0.05`
   means "5 % above p95". No forest is trained for the autoencoder version;
   a stale `version_autoencoder.forest` is ignored on load and deleted at
   the next retrain.
8. **Anomaly attribution is the autoencoder's per-feature error**, not a
   per-feature z-score from the mean — the reconstruction error names the
   feature that stopped agreeing with the rest, the actual reason a joint
   model objected.
9. **Scores run downward.** A point is flagged when its score falls below
   `−decision_margin`; the lowest score is the worst point, and
   `severity = −score / margin` says how far past the line it is.

## Tests

`./tests/anomaly_test.sh` builds and runs the unit suites (890 checks:
preprocessing golden vectors, decision maths checked against scikit-learn, bit-exact
blob round-trips, corrupt-file rejection, streaming mechanics, window
routing, calibration and fine-tune, all HTTP routes, organizations, roles, model ownership and API keys,
configuration layering (flag over environment over file),
CSV/JSON/JSONL import and its timestamp ordering,
the MCP endpoint — every tool, what each role sees, the scratch namespace,
the 401 challenge and the protected-resource document —
GPU/CPU-backend bit-parity), a CLI
end-to-end pass, a live served-over-curl smoke test, and
`tests/authflow_test.sh` — the whole authentication path over a socket
against `oauth`'s own signing test provider, including every deliberately
broken token it can mint being refused, and a viewer and an administrator
driving `/mcp` with real tokens. The whole suite is AddressSanitizer /
LeakSanitizer-clean (`NURL_SAN=1 ./tests/anomaly_test.sh`).
