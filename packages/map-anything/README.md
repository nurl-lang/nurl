# map-anything

Metric 3-D reconstruction from plain images, in pure NURL.

This is a port of Meta's **MapAnything** — reference implementation and paper at
[facebookresearch/map-anything](https://github.com/facebookresearch/map-anything) —
running the Apache-licensed `facebook/map-anything-apache` checkpoint. Given a set
of photos or a video, it predicts for every view: ray directions, depth along ray,
camera pose (quaternion + translation) and a global metric scale, and fuses them
into a metric world-space point cloud. The cloud is written as PLY and can be
orbited in the browser through the [ply](../ply) package's built-in WebGL viewer.

## Usage

```
map-anything photos/            # folder of images -> cloud.ply
map-anything walk.mp4           # video (MJPEG AVI in pure NURL, rest via ffmpeg)
map-anything photos/ --view     # open the browser viewer when done
map-anything hill.mp4 --mask-sky   # outdoor: drop sky via skyseg.onnx
map-anything walk/ --max-views 400 # long capture: windowed + Sim3-stitched
```

`--max-views N` (default 24) uses N views spread over the whole capture: the
frames are split into N runs and each run gives its sharpest frame. A video is
sampled across its whole length for that — three candidates per view, evenly
spaced — so a ten-minute walk gives views from all ten minutes, not its first
seconds. `--fps N` extracts at a fixed rate instead.

### As a web service

```
map-anything serve --host 0.0.0.0 --port 8807 --password "$PW"
```

serves a page where photos or a video are dropped in the browser. Each upload
becomes a job that waits its turn for the GPU; the page follows its progress
and, once it is done, opens the cloud in the WebGL viewer or downloads it as a
PLY. The jobs (inputs, options, log, `cloud.ply`) are kept under
`~/.map-anything/jobs/` (`--data DIR`), so a restart loses nothing and an
interrupted job runs again. Each job runs as `map-anything <input> -o ...`, a
child of the server, so the card is free between jobs.

| route | |
|---|---|
| `GET /` | the upload page |
| `GET /view?cloud=URL` | the ply viewer |
| `GET /api/jobs` | every job, newest first |
| `POST /api/jobs` | `{"name": ...}` → a new job |
| `PUT /api/jobs/:id/files/:name?offset=N` | a piece of an input file as the raw body, appended at byte N |
| `POST /api/jobs/:id/start` | `{"max_views", "fps", "stride", "pixel_stride", "conf_pct", "window", "mask_sky"}` |
| `GET /api/jobs/:id` | one job with its log |
| `DELETE /api/jobs/:id` | the job and its files |
| `GET /jobs/:id/cloud.ply` | the result |
| `GET /healthz` | liveness (never behind the password) |

Without `--password` (or `$MAP_ANYTHING_PASSWORD`) the service is open to anyone
who can reach it: keep it on a private network then. Basic sign-in sends the
password with every request, so off loopback it needs TLS: a TLS-terminating
proxy in front (an ingress), or `--tls-cert FILE --tls-key FILE`.

### 3-D objects

```
map-anything walk.mp4 --scene walk.scene              # keep the views
map-anything mesh walk.scene -o walk.glb              # the whole scene
map-anything mesh walk.scene -o chair.glb --box -0.4 0.1 1.2 0.5 0.9 2.0 --res 320
```

`--scene` keeps what a mesh needs and a point cloud has lost: each view's
camera, depths, mask and colours. `mesh` fuses them into a signed distance
grid inside a box (in the point cloud's coordinates; default the whole scene
without its 2 % outliers), extracts the zero surface, drops the loose pieces
and writes a binary glTF (+Y up, centred on the box, metres) that Blender,
three.js and phone AR viewers open. `--res` is the number of cells along the
box's longest side (default 256): a tighter box gives finer detail.

In `serve` this is the "make 3-D object" button in the cloud viewer: drag the
region's sliders around the object, press it, and open or download the result.

### Beyond the reference: cleaner clouds

```
map-anything walk.mp4 --align 3 --mv-check 1 --voxel auto
```

A feed-forward model's views agree closely but not exactly. Three optional
steps (on by default in `serve`) work on what that leaves:

- `--align N` — per-view Sim(3) alignment inside each window: the parallel
  copies of a wall that the views disagree on are pulled onto each other
  (pairs by projection, closed-form fits, N Gauss–Seidel sweeps).
- `--mv-check N` — a pixel survives only where N other views see the same
  surface at the same depth (`--mv-tol`, default 3 %): floaters go.
- `--voxel M|auto` — one averaged point per M-metre cell; `auto` picks two
  pixels' footprint at the median depth. Less noise, a fraction of the size.

The reference's own masks (non-ambiguous, depth+normal edges, `--conf-pct`,
`--mask-sky`) still run first.

Up to `--window` views (default 24) the whole set runs through the
model's global attention at once. Longer captures are reconstructed in
overlapping windows and stitched with a closed-form Sim(3) fitted on the
overlap views' pixels — exact correspondences, no matching step.

The checkpoint (~4.5 GB, F32 safetensors) is fetched from Hugging Face on first
use via the [hub](../hub) package and cached under `~/.nurl/models`.

## Architecture (from the reference)

- `encoder` — DINOv2-giant, 24 layers, dim 1536, patch 14
- `info_sharing` — 16-layer alternating attention (frame-wise / global) over all
  views, 24 heads, SwiGLU MLP
- `dense_head` — DPT head predicting ray directions + depth + confidence + mask
- `pose_head` — per-view quaternion + translation
- `scale_head` + `scale_token` — global metric scale
- optional geometric-input encoders (known intrinsics / depth / poses) exist in
  the checkpoint; image-only inference uses none of them

Every ported stage is verified against the reference PyTorch modules by importing
and driving them directly, not by re-implementing the math in a second oracle.

## License

Apache-2.0, matching the upstream reference implementation and checkpoint.
