# Changelog

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
