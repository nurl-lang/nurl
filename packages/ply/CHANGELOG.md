# Changelog

## 0.2.3

- Requires `http ^0` instead of `^0.3`. http has been 0.4.0 since #1014
  and 0.4.0 is what this package is built and tested against in the
  repo, but the manifest still asked for `^0.3` — so an install from the
  registry resolved http 0.3.2 and compiled against different code than
  anything here was tested on. `nurlpkg publish` refuses on exactly that
  mismatch, which is how it surfaced. The caret sits on the major so a
  0.x minor release of http cannot silently re-open the same gap in
  every consumer.
- `--version` reports the manifest version.

## 0.2.2 — 2026-07-29

- Viewer: a 4-thread worker pool instead of a single-threaded accept
  loop — a second browser (or a second machine, with --host) no longer
  queues behind the first client's download.
- Rides on the stdlib ChaCha20-Poly1305 rewrite in the same change:
  a TLS cloud download went from ~27 MB/s to ~170 MB/s served, past
  gigabit wire speed. (Ships to installed toolchains with the next
  release; the pool applies immediately.)

## 0.2.0 — 2026-07-29

- **`--host` / `--addr`** on `ply view`: the bind address. The default
  stays 127.0.0.1 (private to the machine); `--host 0.0.0.0` serves
  every interface, a specific address serves exactly that adapter.
- **`--tls`**: HTTPS with a fresh self-signed P-256 certificate
  generated at startup (std/x509_gen, CN ply.local, 30 days) — the
  browser warns once, but the cloud crosses the LAN encrypted. The PEMs
  are staged through unpredictable temp paths and unlinked after the
  listener exits.
- `vw_serve` grew `tls` as its sixth parameter (breaking for callers;
  lingbot-map ≥ 0.9.0 and map-anything ≥ 0.4.0 carry the new flags
  through their own `view` / `--view`).

## 0.1.1 — 2026-07-28

- Viewer: horizontal drag was inverted, in both orbit and pan — dragging
  left rotated (and walked) the scene right. World up is -Y (OpenCV
  axes), which mirrors the screen's horizontal axis relative to a +Y-up
  orbit: the vertical signs come out right on their own, the horizontal
  ones had to be flipped. Vertical behaviour is unchanged.

## 0.1.0 — 2026-07-28

Extracted from `lingbot-map` 0.7.0 (the PLY section of `src/main.nu`,
`src/viewer.nu` and `views/viewer.html`); the history of the code before
this point is that package's.

- Streaming writer: `ply_create` / `ply_vertex` / `ply_finish`, binary
  and ascii, fixed-width count placeholder patched in place at the end,
  ~4 KB write buffering, caller-provided comment line.
- The WebGL2 viewer page, embedded: orbit/pan/zoom, point size, density
  (seeded-shuffle uniform sampling), percentile far-trim, rgb / height /
  depth colouring, `?probe=N` headless render check.
- `vw_serve`: page + cloud on localhost over the http package.
- CLI: `ply view <cloud.ply> [--port n] [--page f]`, `ply info`, and
  `ply <cloud.ply>` as shorthand.
