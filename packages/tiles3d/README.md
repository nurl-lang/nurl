# tiles3d

**OGC 3D Tiles 1.1** tilesets in pure NURL. 3D Tiles is how large 3-D data
streams: a tree of tiles, each with a bounding volume, a *geometric error*
and, optionally, content (a glTF file in 1.1). The geometric error says how
wrong the scene looks, in metres, if the tile is drawn and its children are
not. A client walks the tree and loads only the tiles whose error would
show on screen.

CesiumJS reads tilesets, and so do Cesium for Unreal and Cesium for Unity,
which stream them into a game engine.

This package is the format only. It builds the tree and writes
`tileset.json`. What goes into the tiles (points, meshes) and how the space
is divided belong to the caller; [glb](../glb) writes the content.

```nurl
$ `deps/tiles3d/src/tiles3d.nu`

@ main → i {
    : ~ Tileset t ( ts_new 8.0 )                         // error with nothing drawn
    : i root ( ts_tile t -1 0.0 0.0 0.0 4.0 4.0 1.0 4.0 ) // centre, half sizes, error
    ( ts_refine t root TS_ADD )                           // children add to the root
    ( ts_content t root `root.glb` )
    : i a ( ts_tile t root -2.0 0.0 0.0 2.0 4.0 1.0 0.0 )
    ( ts_content t a `a.glb` )
    ?? ( ts_write t `tileset.json` ) { T _ → {} F e → { ( nurl_print ( string_data e ) ) ^ 1 } }
    ^ 0
}
```

| function | |
|---|---|
| `ts_new gerr → Tileset` | an empty tileset; `gerr` is the error when nothing is drawn |
| `ts_tile t parent cx cy cz hx hy hz gerr → i` | a tile with an axis-aligned box (centre and half sizes) and its error; the first tile is the root (parent `-1`) |
| `ts_content t tile uri` | the tile's content, relative to the tileset |
| `ts_refine t tile TS_ADD \| TS_REPLACE` | how children refine it (the root must say; others inherit) |
| `ts_transform t tile m` | a 4x4 transform, 16 numbers in column-major order |
| `ts_count t → i` | tiles so far |
| `ts_json t → !String String`, `ts_write t path → !v String` | the JSON text, or the file |

**Checked before writing:**
- There is one root, and every parent is a tile made before its child.
- The root states its refine mode.
- No tile's error is above its parent's, and the tileset's error is at least the root's.
- Every number is finite; errors and half sizes are not negative.

A tileset that breaks a rule is refused with the tile's index and the reason.

**Frames.** A tileset is z-up, and glTF is y-up. Clients turn glTF content
to z-up as they load it (+90 degrees about x). So a point `(x, y, z)` of the
tileset goes into a glTF tile as `(x, z, -y)`.

## Tests

```
cd packages/tiles3d
sh tests/tiles3d_test.sh
VALIDATORS="/absolute/path/to/validators" sh tests/tiles3d_test.sh   # after npm install 3d-tiles-validator gltf-validator there
```

The test writes a 21-tile terrain of point tiles in two levels with ADD
refinement, plus the seven tilesets that must be refused. It checks the tree,
that errors fall downwards, that every point lies inside its tile's box, and
that each terrain point is in exactly one tile. With `VALIDATORS` it also runs
CesiumGS's tileset validator and Khronos's glTF validator on every tile.
Running both is necessary: the tileset validator alone accepts content it
cannot recognise.
