### Fixed

- **lingbot-map: camera poses were applied inverted** (lingbot-map 0.13.0). The pose encoding decodes to camera→world; the port inverted it as if it were world→camera, rotating every frame the wrong way round its camera — a fan of rotated room copies on a phone turning in place, tangled facades on the courthouse walk. The reference-side test oracles shared the misreading and are corrected; port and reference agree on the fixed cloud.

### Added

- **recon-kit: the reconstruction service as a package** (recon-kit 0.1.0, map-anything 0.11.0). map-anything's web service, 3-D objects, voxel fusion and frame choice, generalised over an `RkApp` a model package supplies.
- **lingbot-map serve and mesh** (lingbot-map 0.13.0): the same upload page, job queue, viewer and 3-D objects as map-anything, plus `--max-views`, `--scene`, `--voxel` and `--image-size auto` in the CLI.
