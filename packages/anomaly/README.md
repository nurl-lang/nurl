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
  change the cadence. Retraining keeps the margins. The autoencoder is
  left alone unless `schedule.autoencoder` is true, in which case it is
  retrained with the forests, with the layer sizes and pre-filter of its
  last manual training.
- **Multiple time-window versions.** Each model trains one forest per
  enabled version — `short_term` (180 min), `daily` (24 h), `weekly`,
  `seasonal` (90 d) and `timevector` (last 100 points) — so the same stream
  is judged against several horizons at once. A point is anomalous if
  **any** version flags it; the reported score is the most severe.
- **sklearn decision conventions.** `score` is `decision_function`:
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
normal and outlier points. A fixed seed (42, the reference's
`random_state`) makes forests — and therefore scores — byte-identical
across platforms and runs.

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

Fine-tune is calibration plus a write: pick the share of the window you are
willing to alert on and every enabled version gets the margin that flags
exactly that share — rounded to the fewest significant digits that keep the
count, so a margin reads `0.13`, not `0.12994712`:

```
$ anomaly finetune boiler --rate 0.01 --dry-run        # preview, nothing written
$ anomaly finetune boiler --rate 0.01                  # write
$ curl -X POST localhost:8811/api/dynamic/boiler/finetune \
       -d '{"rate": 0.01, "last": 86400, "dry_run": true, "versions": ["daily"]}'
```

The window is counted back from the newest stored point, not the clock, so
a feed that stopped still calibrates on its last day; `last: "all"` is the
whole ring. Ties in the data can make the count land above the target — the
report says what it actually flagged, before and after.

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
  "contributions":[{"feature":"flow","share":0.41},
                   {"feature":"pressure","share":0.19},
                   {"feature":"hour_sin","share":0.14}]}], ...}
```

Contrast that with the reference's `feature_importance`, which is a per-feature
z-score from the column mean: it can only ever point at the value that was
extreme, which is the question the forests were already answering.

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
*tail* the model keeps.

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
audience    = "api://<application (client) id>"   # optional; this is the default
open_ingest = true

[service]
addr    = "0.0.0.0:8811"
webroot = "/usr/share/anomaly/static"
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

**Two roles.**

| | viewer | admin |
| --- | --- | --- |
| the organization's models, their data, the charts | ✓ | ✓ |
| train, finetune, reset, delete, edit metadata | | ✓ |
| API keys, users and roles | | ✓ |

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

#### Azure AD (Entra ID), with `az`

`az ad app create` has no flags for SPA redirect URIs, for exposing an API, or
for the token version, so those three are a Graph PATCH:

```bash
APPID=$(az ad app create --display-name anomaly \
          --sign-in-audience AzureADMultipleOrgs --query appId -o tsv)
          # ...or AzureADMyOrg for a single-organization deployment
OID=$(az ad app show --id "$APPID" --query id -o tsv)
SCOPEID=$(python3 -c 'import uuid;print(uuid.uuid4())')

# 1. SPA redirect URIs, the API this app exposes, and v2 access tokens.
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OID" \
  --headers "Content-Type=application/json" --body "$(cat <<JSON
{
  "spa": { "redirectUris": [
      "https://<your-host>/oauth/callback",
      "http://localhost:8811/oauth/callback" ] },
  "identifierUris": [ "api://$APPID" ],
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

## CLI

```
anomaly detect <model> key=val ...     # ingest one point → verdict JSON
anomaly score  <model> key=val ...     # score only (never ingests/retrains)
anomaly batch  [-f FILE] [-H] [-m M]   # stateless CSV scoring (index⇥score)
anomaly train  <model>                 # force a retrain now
anomaly train-ae <model>               # train the autoencoder version
anomaly calibrate <model> [--last S]   # alert rates vs margins over a window
anomaly finetune <model> [--rate R]    # set every margin from a target rate
               [--last S|all] [-n]     #   (-n / --dry-run previews)
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
| `GET /models/dynamic/<m>/anomalies` | re-score the stored ring, cached (see below) |
| `POST /models/dynamic/<m>/claim` | adopt an unclaimed model into your organization |
| `POST /models/dynamic/<m>/import?format=` | import a CSV/JSON/JSONL file of history |
| `DELETE /api/me` | delete your account (right to be forgotten) |
| `GET\|PUT /api/tenants[/<tid>]` | approve organizations (owner tenant) |
| `GET /api/orgs`, `GET\|PUT\|DELETE /api/orgs/<org>/users[/<sub>[/role]]` | administer any organization (owner tenant) |
| `GET /api/auth/config` | what a browser needs to start a sign-in (public) |
| `GET /api/me` | the caller's identity, organization and role |
| `GET\|PUT /api/org/users[/<sub>/role]` | the organization's roster (admin) |
| `GET\|POST /api/org/keys`, `DELETE /api/org/keys/<id>` | API keys |
| `POST /models/dynamic/<m>/reset` | drop data + forests, keep the name |
| `DELETE\|GET /delete_model/<m>` | delete entirely |
| `PUT /api/dynamic/<m>/schedule` | `{"below_max_retrain_frequency": .., "at_max_retrain_frequency": ..}` |
| `GET /models/dynamic/<m>/calibration?last=&from=&to=&curve=` | alert rates vs margins over a window of the ring (read-only) |
| `POST /api/dynamic/<m>/finetune` | set margins from a target alert rate — `{"rate": 0.01, "last": 86400, "dry_run": false, "versions": [..]}` |
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
| `/modeltrainer.html` | import a CSV/JSON/JSONL file of history; feed points (`/detect`) one at a time or in bulk; force-train |
| `/visualize.html` | plot any numeric feature of a model's stored points over time |
| `/admin.html` | the organization: users and their roles, API keys, model ownership |
| `/anomalies.html` | scan stored history over a time range: score timeline, a per-version ribbon showing *what* flagged *when*, any feature's own trace for context, and a table naming the features whose relationship broke. Filter chips isolate the joint (autoencoder) anomalies from the per-feature (forest) ones |

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

## Known divergences from the Python reference

Deliberate, all documented in the code:

1. **Fine-tune sets a rate, not 95 % of the worst score.** The reference
   initialises its accumulator to `-inf` and only updates on `score <
   -inf`, so it never adjusts anything (and its "+5 % buffer" comment
   belies a `* 0.95`). Its intent — the worst point seen lands just inside
   the band — makes every margin a function of one outlier. Here fine-tune
   is calibration plus a write: the margin that flags a chosen share of a
   recent window, in place (no `tune_<name>` clone).
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
7. **The autoencoder's margin is relative, not absolute.** The reference
   sets `is_anomaly = mse > reconstruction_threshold` in the autoencoder
   branch and then, at the same indentation as the branch, unconditionally
   overwrites it with `is_anomaly = bool(score <= -decision_margin)` using
   the autoencoder default `0.05`. On a threshold of ~5e-4 that requires a
   reconstruction error ~100x the p95 of the training errors — the joint
   detector is effectively off, which its `"enabled": False` default hid.
   Here `decision_margin` is a fraction of the model's own threshold, so
   the stored `0.05` means "5 % above p95" and needs no migration. The
   reference's retrain loop also trained a zero-tree forest for the
   `autoencoder` version config and scored it as a second "autoencoder"
   verdict with the relative margin read as an absolute one; that forest is
   never trained here, and a stale `version_autoencoder.forest` is ignored
   on load and deleted at the next retrain.
8. **Anomaly attribution is the autoencoder's per-feature error**, not a
   per-feature z-score from the mean. A z-score can only name the extreme
   value; the reconstruction error names the feature that stopped agreeing
   with the rest — the actual reason a joint model objected.

## Tests

`./tests/anomaly_test.sh` builds and runs the unit suites (430+ checks:
preprocessing golden vectors, sklearn-parity decision maths, bit-exact
blob round-trips, corrupt-file rejection, streaming mechanics, window
routing, calibration and fine-tune, all HTTP routes, organizations, roles, model ownership and API keys,
configuration layering (flag over environment over file),
CSV/JSON/JSONL import and its timestamp ordering,
GPU/CPU-backend bit-parity), a CLI
end-to-end pass, a live served-over-curl smoke test, and
`tests/authflow_test.sh` — the whole authentication path over a socket
against `oauth`'s own signing test provider, including every deliberately
broken token it can mint being refused. The whole suite is AddressSanitizer /
LeakSanitizer-clean (`NURL_SAN=1 ./tests/anomaly_test.sh`).
