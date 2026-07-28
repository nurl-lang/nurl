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
        ...
        ? ( ply_finish w ) {} { /* the file cannot be trusted */ }
    }
    F e → { ... }
}
```

The layout is `x,y,z` float32 + `red,green,blue` uchar — 15 bytes a
vertex in `binary_little_endian`, one line a vertex in `ascii`. MeshLab,
CloudCompare, Blender and f3d all open it.

## The viewer

One self-contained WebGL2 page, compiled into the binary (an installed
tool has no `views/` directory; `--page FILE` overrides it while editing
the page). It serves `GET /` (the page) and `GET /cloud` (the file,
verbatim) and draws with orbit / pan / zoom, point-size, density and
far-trim sliders, and rgb / height / depth colouring.

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

( vw_serve `cloud.ply` `127.0.0.1` 8080 `` 0 )   // serves until killed
```

## Tests

```
./tests/ply_test.sh
```

Writer round-trip (binary vs ascii agree, count patched, oracle-parsed),
the server (page + cloud verbatim), and — when chrome/chromium is on
PATH — a real headless render with a lit-pixel assertion.
