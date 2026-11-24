# Changelog

## [0.1.0] — 2026-11-23

### Added

- First release, out of map-anything 0.10.0: `rk_serve` (the web service, generalised
  over an `RkApp`), `ms_main` (3-D objects from a scene file), the scene file format,
  voxel fusion (`vx_*`) and the sharpest-frame choice (`sh_pick`).
- Sharing: a finished job's read-only link (`POST/DELETE /api/jobs/:id/share`,
  `/s/<token>` without the sign-in) — view and download the cloud and the object,
  change nothing; "Share", "Copy share link" and "Stop sharing" on the page. Tests run a test
  app that answers the model contract without a model: `tests/serve_test.sh`,
  `tests/mesh_test.sh`.
