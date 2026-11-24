### Added

- **New package `tiles3d`: OGC 3D Tiles 1.1 tilesets** (tiles3d 0.1.0). It builds a tileset tile by tile (bounding box, geometric error, ADD/REPLACE refinement, content URI, transform) and writes `tileset.json`. That is the format CesiumJS, Cesium for Unreal and Cesium for Unity stream large 3-D data in. A tileset that breaks the specification is refused with the tile and the reason. Its test writes a 21-tile point terrain, which CesiumGS's `3d-tiles-validator` and Khronos's glTF validator pass with no errors and no warnings.
- **glb writes point clouds** (glb 0.2.0). `glb_points_write` gives a POINTS primitive under an unlit material, which is the content of a 3D Tiles point tile.
