# ply

Write and view PLY point clouds, in pure NURL.

```
ply view cloud.ply            # serve a WebGL viewer on localhost:8080
ply info cloud.ply            # print the header
ply cloud.ply                 # shorthand for view
```

## The writer

Streaming: the vertex count is not known until the last point, so the
header goes out with a fixed-width placeholder and is patched in place
at the end. Nothing is held in memory.

```nurl
$ `deps/ply/src/ply.nu`

?? ( ply_create `cloud.ply` 0 `my-tool 1.0` ) {   // 0 = binary, 1 = ascii
    T w → {
        ( ply_vertex w 0.0 1.0 2.0  255 128 0 )   // x y z  r g b
        // … one call per point
        ? ( ply_finish w ) {} {}   // F: the file cannot be trusted
    }
    F e → {}
}
```

The layout is `x,y,z` float32 + `red,green,blue` uchar — 15 bytes a
vertex in `binary_little_endian`, one line a vertex in `ascii`. MeshLab,
CloudCompare, Blender and f3d all open it.

A `PlyW` is a handle: copies are the same writer and nothing is freed by
hand. A writer whose last owner lets go of it without `ply_finish` is
finished then (flushed, count patched, closed) — call `ply_finish` to
learn whether the file can be trusted.

## Reading

```
$ `deps/ply/src/read.nu`

?? ( ply_read `cloud.ply` ) {
    T c → { /* . c n points; . c xyz 3 a point; . c rgb 3 bytes a point, or empty */ }
    F e → { ( nurl_print ( string_data e ) ) }
}
```

`ply_read` reads a whole PLY point cloud into memory. It accepts ascii or
binary little-endian files whose vertex element comes first; a mesh's faces
after the vertices are ignored. x, y and z may be any scalar type.
Colours (`red`/`green`/`blue` or `diffuse_*`) are read when present: integers
as 0..255, floats as 0..1. Other properties are skipped. Big-endian files, a
list property in the vertex element, and a body shorter than the header
declares are refused with the reason.

## The viewer

One self-contained WebGL2 page, compiled into the binary (an installed
tool has no `views/` directory; `--page FILE` overrides it while editing
the page). It serves `GET /` (the page) and `GET /cloud` (the file,
verbatim) and draws with orbit / pan / zoom, point-size, density and
far-trim sliders, and rgb / height / depth colouring.

**Game mode** (the "game mode" button, or `g`; mouse and keyboard only)
flies through the scene like a game's spectator camera: the cursor is
captured and the mouse turns the head, `w a s d` or the arrows move along
the view and across it, `e` / `q` (or space / ctrl) rise and sink, shift is four
times faster and the wheel sets the speed. There is no gravity and nothing
to collide with. `esc` gives the cursor back, and the orbit carries on
from the view the flight ended on. `?fly=1` opens the page in game mode.

Details that matter more than they look:

- Points are shuffled once with a seeded Fisher-Yates, so the density
  slider draws a uniform sample of the scene instead of a prefix of the
  write order.
- The far-trim slider is a **percentile** of distance from the centre,
  not a distance to guess; reconstruction clouds put sky at plausible
  but enormous depths, and the default keeps the farthest 2 % out.
- World up defaults to **-Y**: reconstruction clouds are usually in
  OpenCV camera axes (x right, y down, z forward).
- `?yaw=&pitch=&dist=&roll=&trim=&ps=` pin a view, for linking or for a
  test; `?probe=N` renders N frames and reports the lit-pixel count so a
  headless test can check what the GPU actually drew.

```nurl
$ `deps/ply/src/view.nu`

( vw_serve `cloud.ply` `127.0.0.1` 8080 `` 0 0 )   // serves until killed; last 1 = https
```

## Tests

```
./tests/ply_test.sh
```

Writer round-trip (binary vs ascii agree, count patched, oracle-parsed),
the server (page + cloud verbatim), and — when chrome/chromium is on
PATH — a real headless render with a lit-pixel assertion.

### Meshes and regions

The viewer page also takes:

- `?glb=URL` — show a triangle mesh from a binary glTF (vertex colours, lit),
  instead of a cloud;
- `?tiles=URL` — stream an OGC 3D Tiles tileset (what [pctiles](../pctiles) writes)
  instead of one cloud. The tree is walked every frame from the eye. A tile in
  view is drawn, and its children are fetched while its geometric error would
  show larger than 2.5 px. Fetches run four at a time, most-needed first. Past
  a budget of points on the GPU (14 M, 3 M on touch screens), the tiles unused
  for longest are let go, then the least needed. `?sse=` and `?budget=`
  override the two numbers. Box volumes, ADD and REPLACE, and point content are
  read; tile transforms and external tilesets are not yet. Game mode flies
  through a tileset as it does through a cloud.
- `?crop=URL` — over a cloud, a region box with sliders; "make 3-D object"
  POSTs `{"box": [x0, y0, z0, x1, y1, z1], "res": n}` to URL and polls GET URL
  for `{state, progress, url, view}` (the protocol `map-anything serve`
  implements).
