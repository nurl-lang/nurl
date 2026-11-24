# Changelog

## [0.2.0] — 2026-11-24

### Added

- `glb_points_bytes` and `glb_points_write` write a mesh's vertices as a point
  cloud: one POINTS primitive (mode 0) with no indices, POSITION with min/max,
  optional COLOR_0, under an unlit material (`KHR_materials_unlit`, listed in
  `extensionsUsed`). A mesh with triangles is refused, as is an empty one.
  Khronos's validator reports no errors and no warnings.

## [0.1.0] — 2026-11-23

### Added

- `glb_mesh_new`, `glb_vertex`, `glb_normal`, `glb_color`, `glb_tri`,
  `glb_vertex_count`, `glb_tri_count`, `glb_bytes`, `glb_write`: one mesh of
  triangles with per-vertex positions and optional normals and RGBA colours,
  written as binary glTF 2.0. Normals are normalised on the way out (a zero
  normal becomes +Z), colours are normalised unsigned bytes (`COLOR_0`, VEC4),
  indices u32; POSITION carries min/max; the material is double-sided white
  PBR. A dangling index, normals or colours on only some of the vertices, a
  colour vector that is not exactly four bytes a vertex, or a position that is
  not finite as f32 is refused. Normals are scaled by their largest component
  before normalising, so any non-zero size keeps its direction.
- `tests/glb_test.sh`: writes a coloured cube and a bare triangle and checks
  the container, the chunks, every accessor against its bufferView, indices,
  min/max, unit normals and the winding against the normals, without
  dependencies; with `GLTF_VALIDATOR` set it also runs Khronos's validator
  (no errors, no warnings).
