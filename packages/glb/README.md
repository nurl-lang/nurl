# glb

Write triangle meshes as **binary glTF 2.0** (`.glb`) in pure NURL — the
one-file 3-D format that Blender, three.js, the Windows 3D viewer and Android's
Scene Viewer open directly.

```
$ `deps/glb/src/glb.nu`

: ~ GlbMesh m ( glb_mesh_new )
: i a ( glb_vertex m 0.0 0.0 0.0 )  ( glb_normal m 0.0 0.0 1.0 )  ( glb_color m 255 0 0 255 )
: i b ( glb_vertex m 1.0 0.0 0.0 )  ( glb_normal m 0.0 0.0 1.0 )  ( glb_color m 0 255 0 255 )
: i c ( glb_vertex m 0.0 1.0 0.0 )  ( glb_normal m 0.0 0.0 1.0 )  ( glb_color m 0 0 255 255 )
( glb_tri m a b c )
?? ( glb_write m `tri.glb` `my tool 1.0` ) { T _ → {} F e → { ( nurl_print ( string_data e ) ) } }
```

| function | |
|---|---|
| `glb_mesh_new` | an empty mesh |
| `glb_vertex m x y z → i` | a vertex; returns its index |
| `glb_normal m nx ny nz` | the last vertex's normal (normalised when written) |
| `glb_color m r g b a` | the last vertex's colour, 0..255 |
| `glb_tri m a b c` | a triangle, counter-clockwise seen from its front |
| `glb_vertex_count m`, `glb_tri_count m` | sizes |
| `glb_bytes m generator → !( Vec u ) String` | the file in memory |
| `glb_write m path generator → !v String` | the file on disk |
| `glb_points_bytes m generator`, `glb_points_write m path generator` | the vertices as a point cloud |

Normals and colours are all-or-nothing: give every vertex one, or none. A mesh
with some, or with a triangle naming a vertex that does not exist, is refused
with a message.

glTF's frame is right-handed with **+Y up** and the front facing +Z. Convert
your own frame before writing — an OpenCV camera frame (+Y down, +Z forward)
becomes `(x, -y, -z)`.

The file is one scene node holding one mesh with one primitive: POSITION (f32,
with min/max), NORMAL (f32, unit), COLOR_0 (u8 normalised, VEC4), u32 indices,
under a double-sided white PBR material so vertex colours show unchanged.

**Point clouds.** Give vertices and no triangles, and write with
`glb_points_write`. The primitive is POINTS (mode 0) with no indices, under an
unlit material (`KHR_materials_unlit`): points have no normals to light, so
their colours show as they are. This is the form 3D Tiles point content takes.
A mesh with triangles is refused here, and a point cloud is refused by
`glb_write`.

`tests/glb_test.sh` checks the output without dependencies (container, chunks,
accessor bounds, indices, min/max, unit normals, winding against normals) and,
with `GLTF_VALIDATOR=<dir with node_modules/gltf-validator>`, with Khronos's
validator: no errors, no warnings.

## License

MIT OR Apache-2.0
