# Changelog

## [0.1.0] — 2026-11-24

### Added

- `oc_build` builds an octree in which every point is in exactly one node.
  A node keeps one point per cell of its sampling grid, chosen from a seeded
  shuffle, and passes the rest to its octants. A node with at most
  `capacity` points is a leaf.
- Accessors: `oc_count`, `oc_parent`, `oc_level`, `oc_points`,
  `oc_center`, `oc_half`, `oc_spacing`, `oc_min`, `oc_max`, `oc_used` and
  `oc_dropped`. Nodes are numbered parents first.
- Non-finite points are dropped and counted. The root's minimum size and
  the smallest cube that is still halved scale with the coordinates'
  magnitude, so one point repeated many times and georeferenced data both
  end in sensible leaves rather than at the depth limit with boxes below
  float64's resolution.
