# recon-kit

Everything around a 3-D reconstruction model except the model: the web
service, 3-D objects, voxel fusion and frame choice. `map-anything` and
`lingbot-map` are built on it, and offer the same page.

## The service

A model package hands `rk_serve` an `RkApp` and gets `<model> serve`:

```
map-anything serve --host 0.0.0.0 --port 8807 --password secret
```

A browser — a phone too — uploads photos or a video; jobs queue on disk
under `~/.<model>/jobs/` and run one at a time on the GPU as children of
the model's own executable, whose output is the job's log; the finished
cloud opens in the [ply](../ply) viewer or downloads as a PLY; a box in
the viewer cuts a region and "make 3-D object" turns it into a binary
glTF. A restart loses nothing, a shutdown re-queues the job it ends, and
one server owns a data directory at a time. Sign-in is HTTP Basic: put
a TLS proxy (an ingress) in front of anything but loopback.

**Sharing.** "Share" on a finished job makes a link, `/s/<token>` (128
random bits), that opens without the sign-in: a page with the cloud —
and the 3-D object, when one was made — to view or download. Every route
under `/s/` only reads; the viewer comes without its crop tool; the
page sends `Referrer-Policy: no-referrer`. "Stop sharing", or deleting
the job, ends the link.

```nurl
$ `deps/recon-kit/src/serve.nu`

@ my_app → RkApp {
    ^ @ RkApp {
        ( string_from `my-model` )            // name: title, realm, log lines
        ( string_from `photos in &rarr; a cloud out` )   // tagline
        ( string_from `A NURL port of ...` )  // footer (HTML)
        8809                                  // default port
        ( string_from `.my-model` )           // default data dir under $HOME
        ( string_from `MY_MODEL_PASSWORD` )   // password variable
        ( string_from `<div>...the model's option fields...</div>` )
        ( string_from `function modelOptions() { return {...}; }
function modelHint(n, isVideo, picked) { return ""; }` )
        24                                    // views slider default
        120                                   // and its top
        \ Json j → String { ^ ( my_opts j ) } // start request → CLI options
    }
}
```

The options line is built from validated numbers and fixed words
(`rk_jint`, `rk_jbool`, `rk_push_voxel` help); the service refuses one
with anything but `[a-z0-9 .-]` before it reaches a shell.

What the model's executable must answer:

```
<bin> <input> -o cloud.tmp.ply --scene scene.bin <options line>
<bin> mesh scene.bin -o object.tmp.glb --box x0 y0 z0 x1 y1 z1 --res N
```

`<input>` is a video file or a directory of photos; exit 0 with both
files written. The second is `( ms_main name )`.

## The rest

| module | |
|---|---|
| `scene.nu` | the views a run keeps: per view a similarity (camera → cloud frame), a pinhole, z-depths, a mask, colours; refused when cut short |
| `mesh.nu` | `ms_main`: TSDF fusion in a box, marching tetrahedra, loose pieces dropped, written as glTF via [glb](../glb) |
| `voxel.nu` | `vx_new` / `vx_add` / `vx_write`: one averaged point per occupied cell |
| `sharp.nu` | `sh_pick`: n frames spread over a capture, the sharpest of each run (variance of the Laplacian) |

## Tests

```
cd packages/recon-kit && sh tests/serve_test.sh && sh tests/mesh_test.sh
```

No GPU and no model: `tests/app.nu` is a test app that answers the
contract — it serves, it meshes with the real `ms_main`, and its
reconstruction fails the way an undecodable input does.
