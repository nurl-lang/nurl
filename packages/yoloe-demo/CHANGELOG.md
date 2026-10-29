# Changelog

## [0.3.9] — 2026-10-29

### Fixed

- The wasm detector keeps its frame in one Image for the whole loop. It
  built an Image from the frame buffer on every frame. That Image took
  the buffer over and released it when the frame ended, so the next
  frame was written into freed memory. The compiler now rejects the old
  shape (agora #160).

## [0.3.8] — 2026-10-29

### Fixed

- Requires yoloe 0.8.3, whose tokenizer compiles under the current
  ownership rules.

## [0.3.7] — 2026-10-21

### Fixed

- Requires yoloe 0.8.2, whose image packing compiles again.

## [0.3.6] — 2026-10-15

### Changed

- Requires yoloe 0.8 (owned `Camera` and `XWin`). No change here.

## [0.3.5] — 2026-10-14

### Changed

- Requires onnx 0.12, whose run entry points take the input as a checked
  byte view and whose tensors own their device buffers. No change here.

## [0.3.4] — 2026-10-14

Requires gpu 0.17, onnx 0.11.2 and yoloe 0.7.5.

### Changed

- No `unsafe` outside the wasm module's host-import wrappers (14 → 5).
  The server's state is split by what a request does to it: what main
  sets up once (`DemoConf`) is read through `arc_get` with no lock, and
  the engine plus the prompt vocabulary (`Vocab`) — which `/prompt`
  grows and every run changes — sit in a `Locked`, checked out for one
  request at a time. Before, handlers changed the `Arc`'s payload
  through `arc_ptr`.
- The text-embedding slab is a `GpuHost`; prompts are encoded with
  `rt_run_tokens_host` and frames run with `rt_run_host` /
  `rt_run_two_host`.

## [0.3.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.3.2 does not compile under it.

### Changed

- `Demo` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of an
  `rcbox`. The share and drop hooks are ordinary safe functions — the Arc
  does the counting — and so are the constructors that build one from a
  whole value; every copy is still the same state, and its last owner
  releases it.
- One fewer function is `unsafe` than in 0.3.2.
- Requires onnx 0.11.

## [0.3.2] — 2026-10-10

Requires NURL 0.72.0 (`slice_of_str`). Loops that walked a string with
`nurl_str_get` — which measures the string from its start on every call,
so a scan is quadratic in the string's length, and nurlc 0.72 warns
about the shape — read through a view measured once (`slice_of_str` +
`slice_byte`). No change in behaviour.

## [0.3.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.3.0 does
not compile under 0.71.0.

## [0.3.0] — 2026-10-03

Needs toolchain 0.69.0, yoloe 0.7 (Vec-returning `img_to_nchw_norm`,
`mask_coeffs`, `mask_logits`), onnx 0.9.1 (`Engine` handle, `rt_download`
returns a `GpuHost`) and http 0.7 (`HttpApp` handle).

### Changed (API)

- `yd_params_free` is removed: the query parameters release themselves.
- The route handlers take the server state as their first argument
  (`h_index Demo d HttpRequest req Params p`, likewise `h_wasm_model`,
  `h_tpe`, `h_detect`, `h_prompt`); `Demo` is a handle the route closures
  capture.
- `yd_load_graph s path * b okcell → OGraph` → `yd_load_graph s path →
  ?OGraph`.

The served page, the `/detect`, `/tpe`, `/prompt` HTTP API and the CLI flags
are unchanged.

### Fixed

**The WebGPU engine runs again.** The gpu package's WGSL kernel set (copied
next to the worker by `tools/build_wasm.sh`) still held onnx's pre-0.7
kernels, so the engine failed with "no WGSL kernel named gk32_…"; it is now
held to the onnx executor's kernel census (gpu / onnx changelogs). In
headless Chrome (SwiftShader WebGPU) the shipped `web/worker.js` detects the
same four objects on the demo frame with both engines — dog 0.8534, …,
identical to 4 decimals — and the same masked frame byte for byte.

`tests/webgpu_worker_test.mjs` sends its exit command when the module is
idle again, not on the result: `host_frame` clears the futex cell before it
waits, so a wake sent between `host_result` and that clear was lost and the
run could hang (it did, for the static engine in Chrome).

**Nothing is released by hand.** The server state (engine, graphs,
vocabulary, embeddings) is a handle the route closures capture instead of a
hand-allocated struct behind a global word; its last owner releases it. The
per-frame buffers (the NCHW input, mask coefficients and logits, the token
row) are Vecs the compiler drops; `yd_params_free` is gone (the query
parameters release themselves).

`/tpe` without `--text-encoder` read past an empty embedding slab; it
answers 400, as `/prompt` does.

## 0.2.9

`yd_params_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.2.8 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
