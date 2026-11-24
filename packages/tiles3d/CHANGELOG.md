# Changelog

## [0.1.0] — 2026-11-24

### Added

- `ts_new`, `ts_tile`, `ts_content`, `ts_refine`, `ts_transform`,
  `ts_count`, `ts_json`, `ts_write`. These build an OGC 3D Tiles 1.1
  tileset (asset version 1.1, axis-aligned box bounding volumes, geometric
  errors, ADD/REPLACE refinement, content URIs and column-major transforms)
  and write its `tileset.json`.
- Tilesets that break the specification are refused with the tile and the
  reason. That covers no tiles, a root without refine, a second root, a
  parent made after its child, a child with more error than its parent, a
  tileset error below the root's, and negative or non-finite numbers.
- The test writes a 21-tile terrain of point tiles. Its own checks cover the
  tree, the error order, every point inside its tile's box, and each point in
  one tile. With `VALIDATORS` set it also runs CesiumGS's `3d-tiles-validator`
  and Khronos's glTF validator on every tile: no errors and no warnings.
