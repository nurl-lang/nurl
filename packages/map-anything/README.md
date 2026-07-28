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
```

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
