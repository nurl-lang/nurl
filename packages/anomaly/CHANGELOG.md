# Changelog

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
