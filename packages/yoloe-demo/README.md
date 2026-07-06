# yoloe-demo — live YOLOE in the browser, served by pure NURL

Open a web page, start your webcam, and watch **open-vocabulary object
detection + instance segmentation** stream back at you in real time —
with **no Python, no OpenCV, no inference engine and no web framework**
anywhere in the stack.

![the demo page](docs/ui.png)

Every frame makes this round trip:

```
browser webcam ── JPEG POST ──▶ http package        pure-NURL HTTP/TLS server
                                image package       JPEG decode (pure NURL)
                                onnx package        YOLOE-v8s-seg, every layer a
                                                    CUDA-C kernel via NVRTC
                                yoloe package       decode + NMS + mask branch,
                                                    masks composited on the frame
                                image package       JPEG encode
               ◀── JSON + jpeg ─┘                   boxes/labels drawn in-browser
```

![a masked frame](docs/masked_frame.jpg)

The page itself is rendered by the **template** package, and `--tls`
mints a self-signed P-256 certificate at startup with **std/x509_gen** —
pure NURL from the TCP socket to the mask pixels.

## Run it

You need the YOLOE-seg ONNX export + its prompt vocabulary (see
`packages/yoloe` — `tools/export.py` produces both) and an NVIDIA GPU
with the driver + NVRTC installed.

```sh
cd packages/yoloe-demo
../../nurl.sh src/main.nu demo
./demo --model ~/yoloe-v8s-seg.onnx --classes ~/yoloe-classes.txt
# → serving http://0.0.0.0:8090
```

Open **http://localhost:8090**, press *Start camera*, done.

To use it from a phone or another machine on the LAN, browsers require a
secure origin for the camera — start with `--tls` and accept the
self-signed-certificate warning:

```sh
./demo --model ... --classes ... --tls
# → serving https://0.0.0.0:8090
```

| Flag | Default | |
| --- | --- | --- |
| `--model FILE` | *(required)* | YOLOE-seg `.onnx` export |
| `--classes FILE` | *(required)* | prompt vocabulary, one class per line (must match the export) |
| `--port N` / `--host A` | `8090` / `0.0.0.0` | listen address |
| `--gpu N` | `0` | CUDA device ordinal |
| `--tls` | off | HTTPS with a fresh self-signed cert |
| `--page FILE` | `views/index.html` | the demo page template |

## The page

* **Start camera** — streams the webcam through the model; **drop any
  image** on the page to run a single frame without a camera.
* **Prompted classes** — chips toggle which of the model's prompt words
  are shown (server-side filter).
* **Confidence slider** and a **masks on/off** switch, applied per frame.
* **Live stats** — fps, server inference ms, round-trip ms, object
  count, and a per-detection list.
* `?auto=1` starts the camera on load (kiosk mode).

## API

`POST /detect` with a JPEG/PNG body. Query: `conf=` (0..1, default
0.25), `masks=` (default 1), `on=` (comma-separated class ids; absent =
all). Response:

```json
{ "ms": 108, "n": 2,
  "dets": [ { "n": "dog", "s": 0.88, "c": 1, "k": 0,
              "x": 138, "y": 227, "w": 167, "h": 306 } ],
  "img": "data:image/jpeg;base64,..." }
```

`k` is the instance colour index (the page's box palette matches the
server's mask palette). `GET /health` answers `ok`.

## Performance

On an RTX 4090 a 640×480 frame takes ~110 ms server-side (≈7–9 fps
end-to-end in the browser) with masks on. The budget is dominated by the
pure-NURL pixel stages (letterbox, JPEG codec), not the network — the
GPU inference itself is a few milliseconds. Kernels compile once at
startup (`warmup` line); the first frame is never slow.

The server is single-threaded on purpose: one GPU engine, sequential
frames, no locking. RSS is flat under sustained load (see the test).

## Tests

`./tests/demo_test.sh` builds the server, starts it against the real
model, and drives `/detect` the way the browser does: baseline
detections on a known image, `on=` class filtering, `conf=` gating,
masks toggle, garbage-body → 400, and a 60-frame sustained run with an
RSS leak watch. Skips cleanly (exit 0) when no model or GPU is
available, so CI stays green.

## Notes

* Browser-side WebGPU (running the whole network **in** the page) is not
  a small step from here: the gpu package's kernels are CUDA-C compiled
  by NVRTC, so an in-browser build needs a WGSL backend for
  `packages/gpu` plus a wasm↔WebGPU host bridge. This demo is the
  host-GPU streaming architecture instead.
* The model's vocabulary is baked at export time in this version.
  `packages/yoloe/src/prompt.nu` already supports runtime text-prompt
  embeddings (`tools/export_promptable.py`) — wiring a free-text prompt
  box into this page is the natural next step.
