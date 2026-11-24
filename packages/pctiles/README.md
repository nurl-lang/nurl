# pctiles

A point cloud as an **OGC 3D Tiles 1.1** tileset, so that a cloud too large
to open at once streams with level of detail. A client loads only the tiles
the camera can see, at the detail it can see them.

```
pctiles build cloud.ply -o tiles/        # → tiles/tileset.json + tiles/n<k>.glb
```

| option | |
|---|---|
| `-o`, `--out <dir>` | where `tileset.json` and the tiles go (created) |
| `--up -y\|+y\|+z` | the cloud's up axis; `-y` (OpenCV) is what reconstructions write and is the default |
| `--capacity <n>` | points a leaf may hold (60000) |
| `--grid <n>` | a node's sampling grid, n³ cells (64) |
| `--seed <n>` | the sample's shuffle (1); the same seed gives byte-identical tiles |
| `-q` | no progress |

**How it works.**
1. The cloud is turned to the tileset's z-up frame and put in an octree ([octree](../octree)). Each node holds an even sample of its region, and every point is in exactly one node.
2. Each node becomes a tile whose content is its own points: a POINTS glb ([glb](../glb)) with colours.
3. The tree is written as `tileset.json` ([tiles3d](../tiles3d)) and refines by **ADD**: the root's sample is drawn first, and children add detail where the camera is close.

A tile's box is the tight bounds of its subtree. Its geometric error is its
sampling spacing (the gap its children fill) times 8. Clients refine a tile
while its error shows larger than a pixel threshold, 16 by default in CesiumJS
and Cesium for Unreal and Unity. With the scale, that default refines until
the gaps between points are about 2 px, which is when a cloud looks solid.
A leaf's error is 0.

The library entry is `pct_build xyz rgb up capacity grid seed dir verbose`,
which takes positions and colours from anywhere, not only a PLY.

## Measured

Courthouse, 286 frames from lingbot-map: 8,602,924 points, a 129 MB PLY.

| grid | tiles | levels | root tile | largest tile | time | memory |
|---:|---:|---:|---:|---:|---:|---:|
| 128 | 400 | 6 | 53,262 | 260,090 | 6.6 s | 656 MB |
| **64** | 568 | 6 | 10,427 | 86,157 | 5.8 s | — |

With the default grid of 64, a viewer has a recognisable scene after one
10,000-point tile (about 170 KB) instead of the whole 129 MB. CesiumGS's
`3d-tiles-validator` reports no errors or warnings on the tileset, and
Khronos's validator none on any of its 568 tiles.

Opened at their default settings in two clients:

| client | tiles loaded for the first view | points | failed |
|---|---:|---:|---:|
| CesiumJS 1.147 (`Cesium3DTileset`, the runtime under Cesium for Unreal and Unity) | 111 | 2,185,264 | 0 |
| the ply viewer (`?tiles=`) | 151 | 2,872,878 | 0 |

## Limits

- glb positions are float32. Around the origin, where a reconstruction stays,
  that is a tenth of a millimetre over a kilometre. A georeferenced cloud
  far from the origin needs tile-relative positions (a translation per
  tile), which pctiles does not write yet.
- The whole cloud is held in memory while it is tiled (about 75 bytes a
  point at peak). Tiling out of core is for later.
- Sparse octants make small leaf tiles (a few points). They are valid, but
  they cost a request each.

## Tests

```
VALIDATORS=<dir with node_modules/3d-tiles-validator and gltf-validator> sh tests/pctiles_test.sh
```

The test tiles a 120,000-point coloured terrain written in OpenCV axes, then
checks:
- Every point is in exactly one tile, at its place turned to z-up, with its colour.
- Every tile's points lie inside its box.
- Errors fall to 0 at the leaves.
- The same seed gives byte-identical tiles, and `--up +z` leaves points as they are.
- The ply viewer draws the root tile in a real browser.
- With `VALIDATORS` set, both validators pass. If that directory also holds
  `node_modules/cesium`, CesiumJS opens the tileset at its defaults, loads
  tiles and fails none.
