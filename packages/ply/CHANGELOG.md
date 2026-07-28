# Changelog

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
