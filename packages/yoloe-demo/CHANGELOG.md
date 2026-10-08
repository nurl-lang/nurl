# Changelog

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
