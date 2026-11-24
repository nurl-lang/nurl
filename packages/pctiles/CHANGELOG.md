# Changelog

## [0.1.0] — 2026-11-24

### Added

- `pctiles build cloud.ply -o dir` writes a point cloud as an OGC 3D Tiles 1.1
  tileset: a level-of-detail octree with one POINTS glb tile per node and
  ADD refinement. Boxes are the tight bounds of each subtree, and geometric
  errors are the sampling spacing. Options are `--up -y|+y|+z`,
  `--capacity`, `--grid` and `--seed`.
- `pct_build` is the library entry and takes positions and colours from any
  source.
- On the 8.6 M-point courthouse cloud: 568 tiles in 5.8 s. CesiumGS's and
  Khronos's validators report no errors or warnings.
