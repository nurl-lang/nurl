# Changelog

## 0.10.0

- **Margins you can read.** `GET /models/dynamic/<m>/calibration` (and
  `anomaly calibrate`) says, per version, what the current margin flags over
  a window of stored data (default the last 24 h, `last=all` the ring) and
  which margin would flag 0.1 / 0.5 / 1 / 2 / 5 / 10 % — plus a 110-point
  rate→margin curve so a dashboard can estimate the alert rate of a typed
  margin without a round trip. Read-only; about a millisecond per row.

- **Fine-tune sets a rate, not 95 % of the worst score.** The old rule
  followed one outlier: whatever the ring's most anomalous point was, the
  margin moved so it was just inside the band, and it wrote eight-decimal
  values with no more meaning than the first two digits. `model_finetune`
  now picks, per version, the margin that flags 1 % of the last 24 h
  (anchored on the newest stored point), rounded to the fewest significant
  digits that keep the count within a tenth of the target. `POST
  /api/dynamic/<m>/finetune` takes `rate`, the window (`last: 86400 |
  "all"`, `from`, `to`), `dry_run` and a `versions` filter, and reports the
  flagged count and rate before and after for every version. The CLI grew
  `finetune [--rate R] [--last S|all] [--dry-run]`.

- **A ghost `autoencoder` forest.** The retrain loop treated the
  `autoencoder` version config as a forest: it trained and stored a
  zero-tree `version_autoencoder.forest`, and the loader scored it as a
  second "autoencoder" verdict that read the AE's *relative* margin as an
  absolute one. The loop skips it, deletes the stale blob, and the loader
  ignores one.

- **The autoencoder can retrain with the forests.** `schedule.autoencoder:
  true` (dashboard checkbox, `PUT /api/dynamic/<m>/schedule`) retrains the
  net on every forest retrain with the hidden layers and pre-filter
  contamination it was first trained with — both are now persisted
  (`prefilter_contamination`, `trained_at`, `retrain_with_forests` in the
  AE JSON) instead of being lost after the first training call. Off by
  default: a drifting AE at margin 0 is the one detector that tells you the
  feed moved, and retraining it silently would hide that.

- **`severity` in every verdict.** `−score / margin`, per version and as
  the maximum in the aggregate: 1.0 is the alert line, 2.0 twice as far
  past it, negative comfortably normal. The one unit-free number an
  operator — or an agent — can compare across versions and models.

- **Dashboard.** Every setting has a tooltip that says what it means, which
  way to move it for fewer or more alerts, and when it takes effect. The
  drawer shows the calibration of the chosen window (1 h … all) next to
  each margin, estimates the alert rate live as you type one, and has a
  fine-tune section with a target rate, a preview table and an apply
  button. Contamination is editable (`auto` or a share), margins accept any
  precision, and the AE row spells out its rule (`flags error ≥ thr ×
  (1 + m)`). The trainer shows severity.

- `anomaly serve` prints the model store it opened: a mistyped `--store`
  or `$ANOMALY_HOME` otherwise served (and wrote) the default store without
  a word. Note the variable is `ANOMALY_HOME`; `ANOMALY_STORE` is nothing.

## 0.9.1

- **The public organization could take the home marker, and then nobody
  could adopt anything.** A fix for a trap on the exact deployment path the
  README recommends.

  `public` is the organization that credential-less points land in while
  `auth.open_ingest` is open — the migration window. On a fresh deployment
  that window is open *before anybody has signed in*, so the first producer
  to send a point created `orgs/public.db`, and the home marker — "the first
  organization this store ever created" — was written to `public`.

  The marker is written once and never revised. So the operator who signed
  in afterwards was not the home organization, and adoption is reserved to
  the home organization: they could never claim a single model that predated
  them. One anonymous point, and the store was unadministrable.

  `public` is now never home. It is not an operator; it is the bucket
  ownerless data waits in, and the first *real* organization takes the
  marker however many points arrived first.

- **The home organization can adopt a model held by `public`.** Adoption
  used to require a model no organization had claimed at all, which left
  everything the open window collected stranded: `public` held it, and
  `public` is not an organization anyone can sign in to. A model gets there
  because a point arrived without a credential naming an owner — the same
  condition adoption exists for — so it is released from `public` and taken
  into the adopting organization.

- Simple mode still records no ownership, and that is deliberate rather than
  an oversight. Claiming into `public` there would strand the models on the
  simple → oidc transition: `public` would hold them, the operator's
  organization would not, and only the home organization can adopt. Leaving
  them unclaimed is what lets the first organization to sign in become home
  and take them.

## 0.9.0

- **A model can have a nickname.** `alias` is ordinary editable metadata:
  `PUT /models/dynamic/<m>/metadata {"alias": "boiler room"}`, or the field
  beside the model's name in the dashboard drawer. The pickers lead with it
  and sort by it, keeping the real name beside it — a model's own name is
  whatever created it, which here is a 32-character hash, and every route and
  every log stays keyed on that. The alias never reaches a file path or the
  feature order, so unlike the name it is free to be edited, hold spaces, and
  be cleared back to empty.

- **Sign-in, organizations, roles, ownership and API keys** (`src/authz.nu`).
  The service was single-user by construction: every route reached every model
  in one flat store. It now has an identity, a tenant and an owner — without
  moving a single stored model.

  **Off by default.** With `ANOMALY_AUTH` unset the resolver hands every
  request an authenticated admin and the service behaves exactly as it did
  before this file existed. A deployment upgrades the binary first and turns
  authentication on when its identity provider is configured, not at the same
  instant. `ANOMALY_AUTH=1` without both an issuer and a client id stays off
  and says so: half-configured, it would refuse every request rather than
  protect anything.

  - **An organization is an OIDC tenant** — the `tid` claim, or the issuer for
    a provider that publishes none. One SQLite database per organization at
    `<store>/orgs/<org>.db`, so the org is *implicit in the file*: no query in
    `authz.nu` carries an org column and none can forget one. An org id
    becomes a filename, so anything that is not a plain GUID is replaced by a
    digest of itself — no input can produce a separator, a `..`, or an empty
    name.
  - **Two roles.** `admin` manages the organization's models, users and keys;
    `viewer` sees only what it owns. The first subject to authenticate from an
    organization becomes its admin — nobody else could have granted it — and
    the last admin cannot be demoted, because an organization with no admin
    can never appoint one.
  - **A model has an owner:** whoever created it. A model with no row is
    *unowned* — what everything predating this release looks like — and stays
    visible to admins so somebody can claim it (`POST
    /models/dynamic/<m>/claim`) rather than being absorbed by whoever signed
    in first. A model created through the open ingest window stays unowned,
    because nobody was there to own it.
  - **API keys** for producers that cannot do an interactive sign-in. A key
    carries the identity and role of its creator, so "you see only your own
    models" holds for a key exactly as it holds for that user's browser.
    Stored as a SHA-256 of the secret: the plaintext exists once, in the
    response that creates it.
  - **A migration window.** `ANOMALY_OPEN_INGEST` (on by default) keeps
    `/detect` and `/detect_only` reachable without credentials while deployed
    producers are moved onto keys, so turning authentication on does not drop
    a single data point. It is a window, not a design.

  Verification is `packages/oauth`: its own JWKS fetch, signature and claim
  checks. `guard.nu`'s `with_oidc_bearer` returns a handler shape the router
  here does not take, and every route needs its own ownership decision anyway,
  so the routes use `oidc_request_identity` behind one `Gate` — the gate
  answers *may this request proceed*, so no handler assembles a policy
  decision out of parts and a route added later cannot forget half of one.

  Two audiences are tried: the configured API audience and then the client id.
  A dashboard that sends either token from the same sign-in is a dashboard
  that works; the alternative is a 401 whose only clue is which of two GUIDs
  the token happened to name.

- **`/admin.html` and browser sign-in.** `static/auth.js` runs the
  authorization-code flow with PKCE in the browser and wraps `fetch` once, so
  every existing page calls the API exactly as before — a page's only new
  obligation is `await Auth.ready()` before its first request. The new page
  manages users and their roles, API keys, and model ownership.

- **Azure AD (Entra ID) app registration**, created with `az` for this
  deployment. Reproducing it elsewhere:

  ```
  az ad app create --display-name anomaly --sign-in-audience AzureADMyOrg
  # then PATCH the pieces `az ad app create` has no flags for:
  #   spa.redirectUris        <origin>/oauth/callback   (SPA + PKCE, no secret)
  #   identifierUris          api://<appId>
  #   api.oauth2PermissionScopes  access_as_user
  #   api.preAuthorizedApplications  the app itself, so its own scope needs
  #                                  no consent prompt
  #   api.requestedAccessTokenVersion 2
  az ad sp create --id <appId>
  ```

  `requestedAccessTokenVersion: 2` is the one that bites: a v1 access token is
  signed by `sts.windows.net`, not by the issuer OIDC discovery advertises, so
  it fails the issuer check for no visible reason.

  README's *Signing in* section carries the whole sequence, with the values
  a deployment fills in for itself.

- **An admin of one organization could see every organization's models.**
  A tenancy bug with the tenancy layer working correctly: a second tenant
  signing in got its own database with nothing in it, exactly as designed —
  and then the listing showed it the whole store anyway.

  The model store is one FLAT directory shared by every organization; only
  the per-organization claim tables say who a model belongs to. The listing
  and `az_may_see` treated `admin` as "no filter", which in a single-tenant
  deployment is the same thing and in a multi-tenant one is every other
  tenant's data. An admin's world is now the set its organization has
  CLAIMED, never the directory listing.

  A model no organization has claimed is now visible to nobody through the
  ordinary path, and adopting one is reserved to the **home organization** —
  the first this store ever created, recorded in `<store>/orgs/.home`.
  Nothing in an unowned model says whose it is, so any admin being able to
  adopt one would let a stranger who signed in from their own tenant, and so
  became an admin of it, take the operator's data.

  `test_cross_org` is the test that would have caught it: one organization's
  admin against another's models, including a name it could guess.

- **Multi-tenant sign-in** (`auth.multi_tenant`, `auth.allowed_tenants`).
  A single-tenant application has one issuer and a token either carries it or
  is refused. A multi-tenant one does not: every organization signs with its
  own, and the provider's discovery document publishes a *template* —
  Entra's multi-tenant authority literally returns
  `"issuer": "https://login.microsoftonline.com/{tenantid}/v2.0"`.

  So there is nothing to pin, and `oidc_discover` refuses it: it cross-checks
  the document's issuer against the one asked for, correctly, and a template
  never matches. The multi-tenant path therefore reads the discovery document
  itself and takes two fields from it — the issuer template and the JWKS URI
  — so nothing about any particular provider is hardcoded. Each token is then
  verified against that template with its own `tid` substituted, which is what
  the provider documents. Both claims sit inside the same signature, so a
  token cannot be moved between tenants.

  The trade is that anyone with a work account anywhere can sign in and have
  an organization created for them. `allowed_tenants` restricts it; empty
  admits any, which is what multi-tenant asks for and is checked twice — once
  to choose which issuer to demand, and again on the verified `tid`, because
  only the second reading has a signature behind it.

- **Two gate mistakes the new tests caught.** The read/write split was applied
  to the route handlers by a positional pass over the file, and the order was
  not the one assumed: `force_train` was classified as a READ — a retrain
  within a viewer's reach — and `anomalies` as a WRITE, closing the one page a
  viewer most needs. The classification is now keyed on the handler's NAME,
  which is a mistake a name-keyed table cannot make.

  And `allow_create` short-circuited the role check: a missing model returned
  "allowed" before any role was consulted, so an ingest key could invent
  models. The flag says a missing model may be brought into being *here*, not
  that anyone may bring it.

- **Import a file of history** (`src/importer.nu`, `POST
  /models/dynamic/<m>/import`, and a file picker on the Trainer page). CSV
  with a guessed delimiter and quoted cells, a JSON array or one wrapped
  under `data`/`points`/`rows`, or JSONL — which is what this service's own
  `/data` route emits, so a model can be moved by exporting and importing it.
  `format=auto` sniffs.

  It is a separate path from ingest rather than a loop over it, and each
  difference is the reason it exists. **Points keep the timestamp the file
  gives them**, because history that all lands at "now" is not history: every
  time window would see one instant and `seasonal` would be as blind as
  `short_term`. Keeping those timestamps means the batch cannot simply be
  appended — the ring is read as a time sequence by every window filter — so
  the two sorted sides are merged, and a file of last year's data lands
  before this morning's points. **The log is written once and the model
  trains once**, at the end; replaying ten thousand points through the
  streaming path would retrain two hundred times.

  A row that cannot be read is counted and named by line rather than failing
  the file, and a file bigger than the ring is a file whose tail the model
  keeps. Importing creates a model, which is a structural act, so it is an
  admin's — and what it creates belongs to the organization exactly like one
  grown from a stream. There is no third kind of model.

  `tests/import_test.nu` (49 checks) covers the parsers and the ordering;
  the auth-flow suite drives a CSV and a JSONL file over a socket and checks
  that an ingest key can import one and still cannot retrain or delete it.

- **A model belongs to the organization, not to a person.** A colleague
  leaving must not take a production model with them, so everyone in an
  organization sees the same models and the *role* decides what may be done to
  one. `models` has no owner column any more — only the database it sits in —
  and `owner_sub` survives as an audit trail of who first sent a point, blanked
  when they leave. Membership is row EXISTENCE, not a non-empty creator: the
  two are different questions, and conflating them meant forgetting a person
  also forgot which organization their models belonged to.

- **A viewer views.** Reading the organization's models, their collected data
  and the charts is what the role is for; creating a model, training,
  finetuning, resetting, deleting and editing metadata are an admin's.

- **Sending points is the organization's act, not a person's.** It is done by
  the organization's key, so it is not on the role axis at all: keys carry an
  `ingest` capability of their own. An ingest key can feed the models its
  organization already has and can do nothing else — not retrain them, not
  delete what it feeds, not create a new model, not even learn that another
  key exists. A producer credential that could delete a production model is a
  hazard, and one that has to be an admin to send a number is a blunt
  instrument. Keys issued before the distinction existed are migrated to
  `ingest`: every one of them was made to feed a model.

- **Keys belong to the organization, and only its admins see them.** There is
  no per-person view of a key because there is no per-person ownership: the
  listing, creation and revocation routes are admin-only, `az_keys_json` has
  no owner filter, and revoking takes no owner check — whoever pressed the
  button that made a key has no more claim on it than any other admin. The controls
  are not disabled in the dashboard, they are absent, with one line saying why.

- **Nothing is created or collected without a credential.** `POST /detect`
  from an unauthenticated caller is now refused: without a credential naming
  an organization there is nothing a point could belong to, and a model made
  from one would be owned by nobody — exactly the shape the ownership rules
  refuse. `auth.open_ingest` stays as the migration window, defaulting to
  **off**, and even open it routes those points into the `public`
  organization rather than conjuring an ownerless model.

- **`auth.mode`: `simple` or `oidc`.** Simple mode is the service as it was
  before sign-in existed — anyone who opens the page sees every model — kept
  as a mode rather than as a fallback, so a deployment that wants it says so.
  What it collects lands in one `public` organization, a real organization
  with a real database, so the two modes share one shape and turning sign-in
  on later does not have to move anything. (`auth.enabled` is still read.)

- **A tenant registry, and an owner tenant.** An organization that signs in
  and has not been approved is recorded as **pending** and refused;
  provisioning one for whoever knocks is how a multi-tenant service fills a
  disk with strangers. Approving, blocking and un-approving happen in the
  dashboard, because the answer changes at runtime and a config key cannot be
  edited by the person doing the approving — `allowed_tenants` in the config
  only ever ADDS, so a decision made in the dashboard survives a restart.

  `auth.owner_tenant` names the organization whose admins administer the
  service itself: the registry, and any organization's members. It is set in
  the configuration file and nowhere else — a tenant that could grant itself
  that from the dashboard would not be an anchor — and it is always allowed to
  sign in, because one that could be locked out would leave nobody able to
  unlock anything. It exists for the repair an organization cannot do for
  itself: when its last admin has left, promoting somebody is an admin's act
  and there is no admin left.

- **The right to be forgotten.** `DELETE /api/me`. The person's row goes and
  with it the personal identifier on anything they made; the organization
  keeps what is the organization's — its models, and the keys that feed them,
  which is why a key now records the role it was issued with rather than
  reading it from a creator who may no longer exist. If they were the last
  member, the organization goes too: its models are deleted from the store,
  then its database. In that order — a crash between the two leaves models
  nobody claims, which an admin can adopt, while the reverse leaves a database
  pointing at models that are gone.

- **Two things that made a working sign-in look like a broken one**, found
  by minting a real token and following it:

  The multi-tenant issuer was derived and then not used. `__az_token_principal`
  still measured every token against the *configured* value, which for a
  multi-tenant deployment is an authority (`.../organizations/v2.0`) that no
  token ever carries — so every token was refused. The derivation existed and
  its helpers were tested; the wiring between them was not, and
  `test_tenancy_wiring` is now the test that would have caught it.

  And `auth.js` booted on the callback page. That page has no token yet —
  that is the entire reason it exists — so `boot()` raised the sign-in card
  over an exchange already in flight, and clicking it started a second
  sign-in that raced the first. The symptom is a sign-in screen that keeps
  coming back while the sign-in itself succeeds every time. The page now sets
  `__AUTH_CALLBACK__` before loading auth.js, and auth.js leaves it alone.

  Both were invisible because a refused token produced a bare 401. It now
  carries the reason, in the body and in an RFC 6750 `WWW-Authenticate`
  challenge (sanitized — part of it is copied from a token, and a CR LF in
  there is response splitting, not a diagnostic), and the sign-in card shows
  it instead of reappearing with nothing to say. The tenant allowlist is
  also checked before the provider is contacted: whether a tenant is admitted
  needs no network round trip.

- **A configuration file.** Everything the service can be told now layers
  `flag > environment > file > default`. The file is TOML (the project's own
  format), found at `--config FILE` / `$ANOMALY_CONFIG`, else
  `<store>/anomaly.toml`, else `/etc/anomaly/anomaly.toml`; the environment
  overlays only where a variable is actually set, so an unset one lets the
  file show through rather than blanking it. `anomaly.toml.example` ships
  beside the README.

  The store directory is deliberately not settable in the file: the file is
  looked for inside the store, so a `store` key would be a file relocating the
  directory it was just found in. A file that does not exist is fine — most
  deployments have none — but one that exists and does not parse stops the
  service with exit 2, because coming up unconfigured because a config file
  was quietly ignored is the failure nobody can see.

- **`tests/authflow_test.sh`** drives the whole path over a socket against
  `packages/oauth`'s signing test provider: no credentials, a real ES256
  token, first-user-becomes-admin, ownership following its creator, keys
  issued/used/revoked, and every deliberately broken token the provider can
  mint — expired, tampered, wrong audience, unpublished kid, `alg: none`,
  HS256 signed with the public key, a CRLF kid — refused. 28 assertions;
  `tests/authz_test.nu` covers the tenancy rules with 69 more.

## 0.8.0

- **The autoencoder's decision margin is relative to its own threshold.**
  This is a correctness fix, and it is the reason a trained autoencoder
  looked like it was doing nothing.

  Every forest version's `decision_margin` is an absolute offset on a
  `decision_function` whose scale sklearn fixes: normal near 0, anomalies
  below, so `0.06` travels between models. The autoencoder's score is
  `reconstruction_threshold − mse`, and MSE has no fixed scale — it is the
  mean squared error of MinMax-scaled features and lands wherever the data
  puts it (~1e-3 on one model here, ~2e-4 on another).

  The Python reference applies its absolute rule to the autoencoder anyway.
  `model_training.py` sets `is_anomaly = mse > reconstruction_threshold`
  inside the autoencoder branch, then — thirty lines later, at the same
  indentation as the branch itself, so unconditionally — overwrites it with
  `is_anomaly = bool(score <= -decision_margin)` using the autoencoder
  default `0.05`. Against a threshold of ~5e-4 that demands a
  reconstruction error a *hundred times* the p95 of the training errors.
  The one version that models the joint distribution was, in practice,
  off. The reference ships it `"enabled": False`, which is why nobody hit
  it. We had ported the arithmetic faithfully, bug included.

  `decision_margin` for the `autoencoder` version is now a **fraction** of
  that model's reconstruction threshold:
  `anomaly ⇔ mse >= threshold · (1 + decision_margin)`. The stored default
  `0.05` reads "5 % above the p95 training error" — the documented intent —
  and needs no migration: the value that was mute becomes the value that
  works. Measured on a 32-feature home-sensor model, on points whose every
  reading is real but whose clock was rotated 12 h so only the *relations*
  are wrong: the autoencoder went from 1/150 to 150/150. The forests, which
  cannot see relations at all, stayed at 15/150 either way.

  `VerVerdict` now carries both `margin` (the effective band, so
  `score <= -margin ⇒ anomaly` holds for every version without exception)
  and `cfg_margin` (the stored number).

- **`model_finetune` reaches the autoencoder.** It iterated `mo.forests`,
  so the one version whose margin is hardest to guess by hand — because
  the error scale is data-dependent — was the one version it skipped. It
  now calibrates the autoencoder on the same rule as the forests
  (`0.95 · |worst score over the ring|`), expressed in relative units.

- **Anomaly attribution: which relationship broke.** `ae_feature_errors`
  exposes the per-feature squared reconstruction error that `ae_mse`
  already computed and threw away, and `model_ae_contrib` ranks it. A
  feature's share is the amount by which it failed to be predictable from
  all the others, so the top entries name the *relationship* that broke
  rather than the largest number in the record. (The reference's
  `feature_importance` is a z-score from the column mean, which can only
  ever point at the value that was already extreme.)

- **`GET /models/dynamic/<model>/anomalies`: scan the stored ring, cached.**
  The dashboard used to re-score stored history one `POST /detect_only` at
  a time, and every one of those loads the whole model — metadata, ring and
  all five forest blobs — to score a single point. On a 7 271-point model
  that is 45 ms each, 329 s for the ring, which is why the page capped
  itself at 500 points.

  The new route does one model load and one pass, filtered by `from`/`to`/
  `last`, `limit`, `only=anomalies`, `versions=`, with `fields=` attaching
  feature values and `contrib=N` the attribution above. Verdicts are cached
  on disk in `scores.bin`. **14 s cold, 0.1 s warm** for the same ring.

  Invalidation is by epoch, not by rule: `Meta.score_epoch` is bumped by
  anything that can change a verdict — retrain, new autoencoder, margin
  edit, version toggle, metadata patch, reset — and an entry stamped with
  an older epoch is stale by construction. Cache rows are keyed on the
  lifetime point counter rather than the ring index, so ring eviction
  shifts nothing; the suite asserts that a point keeps its verdict across
  an eviction.

  A replayed verdict must not see the future, so `__an_score_enc_upto`
  scores a stored point as though it sat at its own ring position: a
  timevector window is built from the points *before* it. A scan therefore
  reproduces `detect_only` exactly, which the suite checks point by point.

- **The Anomalies dashboard is about the joint verdict now.** The old page
  had one feature picker, which was only ever the chart's y-axis but read
  as "interpret this one feature" — a fair reading, since with the
  autoencoder muted the forests really were the whole verdict, and forests
  really are per-feature detectors.

  It now opens on a time range (last hour … everything stored, or a custom
  window), and shows: the score timeline; a **version ribbon** — one row
  per version, a mark wherever it flagged — which makes "the forests
  flagged these spikes, the autoencoder flagged this whole regime" a
  glance rather than a spreadsheet; any feature's own trace for context;
  and a table naming the features whose relationship broke, with bars.
  Filter chips toggle versions, and **only joint** switches every forest
  off to leave exactly the points that are anomalous because of how the
  features relate. A model with no trained autoencoder now says so in
  place, instead of quietly showing only per-feature anomalies. The status
  line reports how much of the scan came from cache.

## 0.7.0

- **The ring size is metadata, not a constant.** `max_data_points` — how
  many raw points a model keeps — was `MAX_DATA_POINTS = 150000` compiled
  in, so a model that should keep a thousand points kept a hundred and
  fifty thousand and there was no way to say otherwise. It is now a
  per-model field: persisted in `metadata.json`, reported by every
  metadata response, and patchable through `PUT
  /models/dynamic/<model>/metadata`. It must be positive and at least
  `min_data_points`, since a ring smaller than the warm-up threshold
  could never train the model at all.

  Lowering it below the current fill evicts the oldest points and
  rewrites the log **before the call returns**. The alternative — let the
  ordinary per-ingest eviction converge on the new cap — means a model
  told to keep 25 points keeps 60 until 35 more arrive, which is not what
  the setting says.

- **The Advanced metadata editor is generated from the metadata.** It
  used to hard-code the editable half as `{schedule, versions}`. So when
  `max_data_points` became patchable through the API it was invisible in
  the one editor that exists to reach it — the editor kept its own copy
  of a list that lives in `model_apply_meta_patch`, and the copy went
  stale the moment the list changed.

  The list is now published: every metadata response carries
  `editable_fields`, built by `meta_editable_fields` beside the code that
  reads the patch. The drawer's Advanced box has two views over exactly
  those keys — **Fields**, a form generated by walking the metadata's own
  shape (one typed input per leaf, checkboxes for booleans, every version
  and every one of its fields, including the geometry and forest sizes no
  hand-written form ever showed), and **JSON**, the raw document. Neither
  view names a field, so the next editable key will appear on its own.
  Switching views carries the edits across; an emptied box is an omitted
  field, and a number that is typed as a word stays a word, because
  `contamination` is legitimately either `0.05` or `"auto"`.

  The Overview also shows the model's own ring size, and the header stat
  is labelled the service *default* now that each model carries its own.

- `tests/dashboard_test.js` covers the generated editor (the slice follows
  `editable_fields`, every leaf becomes one field, an untouched form
  round-trips to the JSON it came from, coercion and omission, and a key
  the service adds later needs no dashboard change). It is skipped when
  node is not installed. `metaedit_test` and `service_test` cover the new
  field and the published key list; the live HTTP pass asserts both.

- A `.gitignore` for the package's build products. `nurlpkg pack` already
  left them out of the tarball — verified, the dry-run manifest is
  byte-identical with and without the file — but the 800 KB extensionless
  `anomaly` executable sat in `git status` as untracked, one `git add -A`
  away from the history.

## 0.6.0

- **The metadata is editable from the dashboard.** `PUT
  /models/dynamic/<model>/metadata` takes the editable half of the
  metadata — the retrain schedule and the per-version configs — as a
  patch in which every field is optional: what the body omits keeps its
  value, an unknown version name adds a version, and
  `"replace_versions": true` deletes the ones the body omits. Values are
  clamped into a trainable range rather than rejected, so a hand-written
  JSON edit cannot produce a version that fails to train. The learned
  half (column kinds, categories, feature order, scaler) is still never
  accepted from a client: it is refitted at every train and a
  hand-written copy would silently desync every forest. Library:
  `model_apply_meta_patch`, `model_set_version_enabled`,
  `meta_apply_versions_json`, `meta_find_version`,
  `meta_version_enabled`, `meta_version_margin`.
- The Model Manager drawer now edits what it used to only print: a
  checkbox and a margin field per version (the two settings that bite at
  the very next detect), and an *Advanced · edit metadata as JSON* box
  holding the same document the route takes, for the geometry and forest
  sizes that take effect at the next retrain. The retrain-schedule form
  goes through the same route.
- **The autoencoder is visible.** It has been trainable since 0.4.0
  (`anomaly train-ae`, `POST /train/autoencoder/<model>`) and its verdict
  has ridden along in every detect, but nothing in the dashboard ever
  said so, so a model's most interesting version was invisible unless you
  read the JSON. `GET .../metadata` now carries an `autoencoder` block
  (trained, enabled, threshold, points trained on, anomalies filtered,
  margin, feature names, layer sizes) — its state lives in
  `autoencoder.json`, not the metadata, which is why it had no place in
  `meta_to_json` — and the drawer has an Autoencoder section that shows
  it and trains or retrains it, hidden geometry and contamination
  included. `POST /train/autoencoder/<model>` accepts an optional
  `{"hidden": [..], "contamination": x}` body instead of always using
  64-32-64 and automatic contamination.
- Disabling the `autoencoder` version now actually mutes it. The verdict
  was gated on the trained net alone and ignored the `enabled` flag its
  own `VerCfg` has carried since 0.4.0, so the one version you could not
  turn off was the one the UI never showed. Disabling it keeps the net —
  unlike a forest version, whose blob is deleted, because a resurrected
  forest would be scoring against a feature order and scaler the model
  has since moved past, and the autoencoder's net carries its own frozen
  feature order.
- Every path dependency is pinned on the major (`^0`) instead of the
  minor, the way `http` already was since 0.5.6. A 0.x minor release of
  `iforest`, `gpu`, `gpukit`, `cli` or `mlp` no longer leaves this
  package resolving an older copy from the registry than the one it is
  built and tested against here.
- Internal: `__an_margin_of` moved to `src/prep.nu` as the shared
  `meta_version_margin`, and `__an_jarr_of_strs` took the
  single-underscore shared spelling — both were about to be called across
  files, which is the compiler's obsolete `__` path.
- `tests/anomaly_test.sh` gained the `metaedit` unit suite (55 checks)
  and live-HTTP coverage of the metadata route; its CLI batch check now
  sorts under `LC_ALL=C`, because `sort -g` reads `0.15` as `0` in a
  comma-decimal locale and silently ranked every row equal.

## 0.5.6

- Requires `http ^0` instead of `^0.3`. http has been 0.4.0 since #1014
  and 0.4.0 is what this package is built and tested against in the
  repo, but the manifest still asked for `^0.3` — so an install from the
  registry resolved http 0.3.2 and compiled against different code than
  anything here was tested on. `nurlpkg publish` refuses on exactly that
  mismatch, which is how it surfaced. The caret sits on the major so a
  0.x minor release of http cannot silently re-open the same gap in
  every consumer.
- `--version` reports the manifest version.

## 0.5.5

- `anomaly --version` reports the version the package actually is. The
  string passed to `cli_new` is hand-written and nothing derived it from
  `nurl.toml`, so it had been answering `0.5.2` through the 0.5.3 and
  0.5.4 releases. `tools/check_package_version_strings.sh` now fails the
  build on that drift, so it cannot happen again silently.

## 0.5.4

- Internal rename, no API change: `_an_vercfg_of_json` was `__`-private
  to `src/prep.nu` and called from `tests/timevector_test.nu`. A `__`
  name is file-scoped, so that call went through the compiler's obsolete
  cross-file compatibility path and warned on every build. It now carries
  the single-underscore shared-internal spelling.

## 0.5.3

- Requirements widened to gpu `^0.11` / gpukit `^0.6`. No source change:
  the published 0.5.2 asked for versions that predate them.

## 0.5.0

**The autoencoder trains on the GPU when one is present — bit-exactly.**
Training was the autoencoder's whole cost (~20 s for 20 k rows on the CPU;
the scoring passes are milliseconds), and it now runs on a CUDA device by
default, with the package's standing guarantee intact: **backend choice can
never change a result**. The GPU-trained network is bit-for-bit identical to
the CPU-trained one — same weights, same threshold, same verdicts — so GPU is
pure speed: **~34× faster** end-to-end on the parity benchmark (6 k × 12,
64-32-64, 3 restarts: 7.6 s → 0.22 s).

- `src/aegpu.nu`: a bit-exact device mirror of `mlp_fit`. Control flow (the
  seeded shuffles, validation split, early stopping, best-weights restore,
  restarts, Adam scalars via host `pow`/`sqrt`) stays on the host; five
  kernels (forward / backprop / gradient / Adam / eval-diff) reproduce the
  CPU's rounding and accumulation order exactly — explicit `__dadd_rn`/
  `__dmul_rn` (no FMA contraction), serial dot products in the CPU's k-order,
  per-weight gradient sums in the CPU's row order. Weights and Adam state
  stay device-resident across the whole run.
- Selection: CUDA present → GPU; otherwise (no device, `ANOMALY_GPU=0`, or
  any mid-setup failure) the pure `mlp_fit` — identical results either way.
  The gpu package's host-C++ backend is deliberately not used for training:
  native `mlp_fit` already is the optimised CPU path.
- `tests/aegpu_parity_test.nu` (+ `tests/aegpu_smoke.sh`) pins the guarantee:
  weights, biases, the full Adam state, epoch count and both loss figures
  are asserted BIT-IDENTICAL between `mlp_fit` and `aegpu_fit`.
- Requires `mlp` ≥ 0.2 — whose frozen-Adam-bias-correction fix this parity
  work uncovered (a scalar step-counter field on a by-value struct never
  advanced; see the mlp changelog).

## 0.4.1

- Widen the gpu requirement to ^0.9 (device-specific CUBIN kernel cache =
  faster process start; pinned-staged uploads). No API change.

## 0.4.0

**The timevector is a real sliding window, and the autoencoder version
arrives.**

- **timevector = sliding window.** Previously the version trained a plain
  point-based forest on the last 100 ring points. Now `window_size`
  consecutive points flatten to ONE window vector (stepped by `step_size`
  during training, both configurable and persisted), the forest trains on
  the window vectors, and detection scores the window ENDING at the
  incoming point — the version that sees ORDER. A reversed pattern or a
  stuck sensor whose every reading is individually in range scores
  anomalous while the point-based versions stay blind. A ring shorter
  than the window yields NO timevector verdict (absent, never silently
  wrong); detection derives the live window from the trained forest's
  width, so a config change can never desync scoring before the retrain.
  Legacy metadata upgrades in place (timevector 100/1).
- **autoencoder version** (over the new [`mlp`](../mlp) package): an
  explicitly-trained reconstruction detector. Training follows the
  reference recipe — a temporary Isolation Forest (contamination 10 %)
  drops the ring's anomalies first, the surviving rows are MinMax-scaled,
  an MLP autoencoder (64-32-64 default, Adam, early stopping,
  deterministic restarts) learns to reconstruct them, and the threshold
  is the 95th percentile of the training errors. Detection reports
  `threshold − mse` in the standard decision_function orientation, so
  the any-version aggregation and margin tuning need no special case.
  It catches CORRELATION breaks the marginals hide (a pressure/flow pair
  that is individually normal but jointly impossible). Train with
  `anomaly train-ae <model>` or `POST /train/autoencoder/<model>`;
  never part of the automatic retrain schedule. Persisted per model
  (`autoencoder.json`, bit-exact weights) and loaded on model open.
- `model_set_version_window` — library-level window configuration.
- Tests: `timevector_test.nu` (19 checks — order-blindness made visible:
  the reversed run scores WORSE on timevector and BETTER on short_term),
  `autoencoder_test.nu` (15 checks — detect/persist/errors), live HTTP
  train + version-in-detect checks. Full suite 30/0; ASan + LSan clean.

## 0.3.6

- The `serve` dashboard now works out of the box after a registry install.
  Declares `[install] assets = ["static"]`, so `nurlpkg install anomaly`
  stages the dashboard HTML into `$NURL_HOME/share/anomaly/static`, which
  `serve` already resolves relative to its own executable
  (`<exe-dir>/../share/anomaly/static`). Before this, only the binary was
  installed and `anomaly serve` silently fell back to API-only unless you
  pointed `--webroot` at a source checkout. Now `anomaly serve --addr
  0.0.0.0:8080` serves the dashboard with no extra flags.

## 0.3.5

- Fix a broken registry install. 0.3.4 bumped the `gpu` requirement to
  `^0.4` but left `gpukit` pinned at `^0.2`; since `^0.2` selects gpukit
  0.2.0 (which itself requires `gpu 0.2`), the two constraints could not
  share a `gpu` version and resolution failed with `ResolveConflict`.
  Bumps `gpukit` to `^0.3` (gpukit 0.3.2 requires `gpu ^0.4`), so the whole
  graph agrees on `gpu 0.4.x`. No code or behaviour change.

## 0.3.3

- Internal: the GPU bulk-scoring path now runs on the [`gpukit`](../gpukit)
  facade — `anom_scores_gpu` drops from ~65 lines of hand-written device
  marshalling to one `gk_run`, and the singleton holds a `*GpuKit` (device +
  cached kernel). Output stays **bit-identical** across CUDA / CPU-backend /
  pure (gpu_test's equality checks still pass on both backends). Adds a
  `gpukit` dependency.

## 0.3.2

- Internal: the command line is now assembled with the [`cli`](../cli)
  package — `main()` drops from ~150 lines of hand-rolled argument parsing +
  dispatch to a declarative Cli. Command behaviour is unchanged; `--help` is
  now auto-generated and colour-aware. Adds a `cli` dependency.

## 0.3.1

- Internal: `anomaly serve` now runs on the [`http`](../http) package's
  `HttpApp` facade instead of a hand-wired listener + server loop. No API or
  behaviour change to the routes; the service additionally gains graceful
  SIGINT/SIGTERM shutdown and handler-panic→500 for free. Adds an `http`
  dependency.

## 0.3.0

- **Web dashboard.** `anomaly serve` now serves a small, self-contained
  dashboard (plain HTML/CSS/JS — no CDN, no build step) alongside the JSON
  API, all pages talking only to the server's own routes:
  - `/` · `/modelmanager.html` — list models; train / finetune / reset /
    delete; edit the retrain schedule; inspect metadata.
  - `/modeltrainer.html` — feed points (`/detect`, `/detect_only`) singly or
    in bulk (paste JSON lines / generate synthetic); force-train.
  - `/visualize.html` — plot any numeric feature of a model's stored points.
  - `/anomalies.html` — re-score stored points via `/detect_only` and
    highlight the anomalies (chart + table with the flagging versions).
- **`--webroot DIR`** for `serve`, auto-located via `$ANOMALY_WEBROOT`,
  `<exe>/static`, `<exe>/../share/anomaly/static`, then `./static`. With no
  web root the dashboard routes 404 and serving is API-only (unchanged).

## 0.2.0

- Streaming self-training models, per-version time windows, fine-tune,
  schedule control, CLI + HTTP/JSON service, GPU-accelerated bulk scoring
  (CUDA / CPU-backend / pure — bit-identical).
