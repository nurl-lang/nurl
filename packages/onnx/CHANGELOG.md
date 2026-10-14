# Changelog

## [0.12.0] — 2026-10-14

### Changed

- No `unsafe` code is left but the kernel census's two dummy device
  buffers (76 functions in 0.11.3).
- An `RTensor` owns its device buffer (a gpukit `GkBuf`, pooled): every
  intermediate is allocated with `gk_dbuf_new` and handed back to the
  kit's pool by its last owner, and an aliasing Reshape, Unsqueeze or
  Split holds a view of the block it aliases. An `RTensor` therefore stays
  readable after `rt_reset` or the next run; `rt_download` of an old one
  reads what that run computed. Its `dptr`, `eng` and `run` fields are
  gone (`buf`, and `hosti` for a host-int tensor, replace them), and it is
  no longer `raw`.
- The engine keeps its state in a `Locked` beside its kit: one run at a
  time per engine, from any number of threads. The graph a run is given is
  borrowed for the run; the initializers are read out of it instead of
  through its `inits` Vec held as a raw handle word.
- `rt_run_shaped`, `rt_run_tokens`, `rt_run_two` and `rt_run` take the
  input bytes as a `( Slice u )` and check them against the shape: a short
  input runs nothing and returns an empty tensor. The `*_host` forms stay.
- An index read of a tensor that is not int64 is no buffer (the kernel
  refuses it); it used to read f32 memory as i64, past the end of the
  block. A Mul/Add/Sub/Div or other kernel over a host-int tensor fails
  the same way: the old executor launched it on the `-1` sentinel address
  and crashed.
- The model parser copies weight blocks out of the checked protobuf view
  in one pass instead of poking them in four bytes at a time (about 3.5
  million instructions fewer on a 1 MB model).
- `slice_f32_into`, `slice_i64_into`, `vec_f32_into`, `vec_i64_into` and
  `otensor_host_ptr` are gone (raw-pointer writers and readers);
  `slice_u32_le` / `slice_u64_le` and `slice_to_vec` do their work.
- Requires gpukit 0.11 with `gk_dbuf_download_bytes` and `gk_dbuf_copy`.

Byte-identical outputs to 0.11.3 on the test models and on an exported
CNN (Conv, dilated Conv, ConvTranspose, BatchNorm, MaxPool, Resize,
Concat, LeakyRelu, Sigmoid, Softmax; 6e-8 from torch); same speed (347
against 346 ms median). Graphs that crashed 0.11.3 (a segfault on a
host-int operand) now report the kernel they could not run.

## [0.11.3] — 2026-10-14

### Changed

- Requires gpukit 0.11: the census (`static_kernels`) reads the recorded kernel names and sources as `String`s of their own.

## [0.11.2] — 2026-10-14

Requires NURL 0.73.0 (grammar v2.9 `raw`, `slice_window`, `file_is_open`).

### Changed

- `RTensor` is a `raw` struct and carries the engine and run it came from: `rt_download` and `dtensor_from_output` refuse a tensor of another engine or of an earlier run, whose device memory `rt_reset` (or the next run) released — they read it before. Needs gpukit 0.10.2.
- 6 more functions are `unsafe`/`raw` than in 0.11.1 (83 now): where they launch kernels of their own, the trust is now written down.
- Requires gpu 0.17. New safe entry points over `GpuHost` buffers: `rt_run_host`, `rt_run_two_host` and `rt_run_tokens_host` check that each input holds its shape's worth (an input too small runs nothing and returns an empty tensor) and need no `unsafe` caller; `rt_run_shaped` / `rt_run_two` / `rt_run_tokens` keep taking raw pointers.

## [0.11.1] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.11.0 does not compile under it.

### Changed

- The runtime's replaced name strings and buffers are dropped by the
  store; the `mem_take` before each is gone.
- The tests build their buffers as `Vec`s instead of raw allocations.
- Requires gpu 0.16.

## [0.11.0] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.10.2 does not compile under it.

### Changed

- `Engine` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of an
  `rcbox`. The share and drop hooks are ordinary safe functions — the Arc
  does the counting — and so are the constructors that build one from a
  whole value; every copy is still the same state, and its last owner
  releases it.
- 2 fewer functions are `unsafe` than in 0.10.2.
- Requires gpu 0.15 and gpukit 0.10.

### Removed

- `rt_none`: an `Engine` is always an engine. A holder that may have none
  keeps a `?Engine`. `rt_ok` no longer has a null handle to answer for.

## [0.10.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.10.1 does not compile under 0.72.0. The functions that do
are declared `unsafe`. An empty protobuf reader and an empty field are
`slice_empty`, where they were a `Slice` built literally over a null
pointer. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.10.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.10.0 does
not compile under 0.71.0.

## [0.10.0] — 2026-10-03

**Engine is a self-releasing handle** (`*Engine` → `Engine`; the last copy
releases the device buffers, kernels and context; `rt_close` is an optional
early release) — a breaking API change, hence the minor bump; needs
gpu ^0.14, gpukit ^0.9, tensor ^0.6 and NURL 0.69.0. Folds in the unpublished
0.9.1 below.

**The WebGPU kernel set is checked against the executor too.** The gpu
package's WebGPU backend looks kernels up by name in a fixed WGSL set
(`deps/gpu/web/kernels_wgsl.js`), which still held the pre-0.7 kernels — the
census that fixed the static backend in 0.9.1 did not reach it, and objdet's
wasm module and yoloe-demo's WebGPU engine failed at run time. New
`tests/wgsl_census_test.nu` (no device, no browser) holds that set to
`rt_kernel_census`: a WGSL kernel for every census kernel, each with exactly
the parameter list the census recorded, every parameter type marshallable,
and no entry the executor no longer launches. New `tests/webgpu_test.sh`
builds `tests/webgpu/run.nu` (one forward on the WebGPU backend, as a
wasm32-wasi command) and runs tiny.onnx on a real WebGPU device in headless
Chrome against the onnxruntime reference (skips without zig, node +
puppeteer, Chrome or an adapter).

Verified on Chrome's WebGPU (SwiftShader): tiny.onnx matches onnxruntime to
7.3e-8 of range; tinyyolov2 matches the CUDA backend to 4.5e-7 of range
(21125 outputs); objdet's wasm module detects car 0.6388 / car 0.5774 /
dog 0.3231, the same boxes and scores as the native CUDA CLI to 4 decimals.

### Included from 0.9.1 (never published)

**The static backend and the wasm builds work again — and their kernel set
can no longer drift from the executor.** `tools/gen_static_kernels.nu`, which
writes the `kernels_static.c` that the gpu package's static backend (no
NVRTC, no host compiler, no dlopen: every wasm32 build, e.g. yoloe-demo's
in-browser engine) links, kept a hand-written mirror of the executor's
kernel list and imported `src/ops.nu` to get the sources. 0.7.0 moved the
executor onto gpukit's kernel library and deleted `ops.nu`; the mirror was
never updated, the generator stopped compiling, and the kernels it had
emitted were not the ones the executor asked for any more (`gemm` vs
`gk32_gemm_tiled`, `int` parameter cells vs `long long`). Every test stayed
green for three releases.

The kernel set is now **derived**, not listed. `rt_kernel_census kit`
(runtime.nu) issues every `gkd_*` call the executor makes — once per variant
a handler can select — on a gpukit *census kit*, which records each kernel's
entry name and exact source from gpukit's own builders while taking the
static backend's branches. `src/static_kernels.nu` turns that record into C
(`onnx_static_kernels_c`); the tool is a thin front end over it. A kernel
the executor gains, or a body gpukit changes, reaches the static set with no
edit to the generator.

- The hand-optimised static conv2d is kept (2.41 s vs 3.14 s per tinyyolov2
  frame, bit-identical), re-cut for the current `gk32_conv2d` parameter
  cells (`long long`). An override now states the exact parameter list it
  was written against; the generator refuses to emit one whose kernel's
  signature changed, or whose kernel the census no longer records.
- The generator refuses a kernel that needs block barriers (`__syncthreads`,
  `__shared__`), which the static backend's serial launcher cannot run.
- New `tests/census_test.nu` (no device, no compiler): every `gkd_*` wrapper
  the package's sources call is exercised by the census, gpukit accepts
  every census call, and `kernels_static.c` generates with every kernel
  registered. New `tests/static_test.sh`: generate, compile (`cc -O2`, and
  `zig cc --target=wasm32-wasi` when zig is present), link into the CLI and
  run `tiny.onnx` with `NURL_GPU=static` against the onnxruntime reference.

Verified on the static backend against CUDA: tinyyolov2, YOLOE-v8s-seg,
YOLOE promptable-k32 and the MobileCLIP text encoder match to float32
rounding (max |Δ| relative to the output's range ≤ 6.2e-6), and are
bit-identical to the CPU (host C++) backend and to the last working static
build (7e536eaa). Per forward, native static (single thread, cc -O2) vs that
build: tinyyolov2 2.42 s (2.41), YOLOE-v8s-seg 17.0 s (19.9), promptable
18.2 s (20.4); the yoloe-demo wasm module (node, -O3 -msimd128) detects the
demo image's dog at 0.853 in 33.0 s per frame.

Requires gpukit's census kit (`gk_open_census`) and the gpu package's static
probe sentinel (`CPU_STATIC_SENTINEL`).

**Nothing is released by hand.** `rt_open` returns an `Engine` handle
instead of a `*Engine` pointer: every copy is the same engine, and its last
owner releases every device block it allocated (now kept as `GpuBuffer`s),
its value map and the device (the kit); `rt_reset` lets a run's blocks go
early, `rt_close` is an optional early release. The graph a run is handed
stays the caller's: the engine keeps copies of its input / output names and
views its initializers for the run, and holds no part of it (so one graph
runs on any number of engines, and no free is needed for it). The input
shapes `rt_run_shaped` / `rt_run_two` are given are `sink` — they always
were adopted by the value map. `rt_download` returns a `GpuHost` (released with its owner;
`gpu_host_ptr` / `gpu_host_get_f32` read it) instead of a `*u` the caller
freed. `OGraph` and `OTensor` are owning structs — an initializer's host
data is a `( Vec u )` now (`otensor_host_ptr` for its address) — so
`graph_free` is an optional early release. New: `rt_none` (an engine that is
not there, `rt_ok` F). Callers change `*Engine` to `Engine`.

## 0.9.0

The package's own protobuf decoder is gone. `stdlib/ext/protobuf.nu` — the
checked codec promoted into the standard library in toolchain 0.64.0 — now
owns the wire format, and `src/pb.nu` is the seam onto it.

The old decoder read a model on trust. Nothing bounded a length prefix, a
varint could shift past 64 bits, and `pb_skip` knew four wire types out of
six: a group tag advanced the cursor by nothing at all. So a malformed
model was not rejected, it was *decoded anyway* — and sometimes not even
that. Over 700 mutations of real models, the old reader silently returned a
graph for 454 of them and **hung forever on 3**, where a corrupt length
prefix drove the cursor past the buffer and the end-of-message test never
came true again. `tests/data/malformed_length.onnx` is one of those three,
kept as a regression: 544 bytes, and it used to spin.

What the parser does with a bad model is now a decision, not an accident:

- **`onnx_parse_checked`** returns the first wire-format error with its
  code and byte offset — `bad-length offset=15` for the fixture above.
- **`onnx_parse`** keeps its old signature and its old contract for the
  six packages that call it: a malformed model yields an empty graph,
  which runs no nodes.

A `PReader` is a checked stdlib reader plus a sticky error. Every read is
infallible where it is called and returns a neutral value once the reader
has failed, so each message parser stays the flat `while more { ... }` loop
it already was — the first failure latches, the loop stops, and a
sub-message carries its failure back to its parent.

`TensorProto.raw_data` is **borrowed in place** now. The old code recorded
the block's offset, let the cursor run on, then rewound to re-read it; the
stdlib reader hands back a slice of the model buffer, so the weights are
decoded straight out of it and the cursor never moves backwards.

Verified against the parser it replaces: **1,918 ONNX models** — the whole
`onnx` backend test corpus plus this package's own fixture — parsed with
both implementations and dumped in full (every node, attribute,
initializer, and a position-sensitive checksum over every weight block).
All 1,918 dumps are **byte-identical**. The dump tool is committed as
`tests/parse_dump.nu`; it needs no GPU. 500 further runs under
ASan/UBSan/LeakSanitizer — 200 real models and 300 mutations — report
nothing.

`nurl-version = "0.64.0"` is now declared: that is the toolchain that first
shipped `stdlib/ext/protobuf.nu`.

### Changed

- `pb_read_f32_into` / `pb_read_i64_into` over a `*PbR` cursor become
  `slice_f32_into` / `slice_i64_into` over a `( Slice u )`, with
  `vec_f32_into` / `vec_i64_into` for a whole byte vector — which is what
  reading a plain little-endian `.f32` file always was. `PbR`, `pb_sub`,
  `pb_pos`, `pb_set_pos`, `pb_blob_start`, `pb_byte`, `pb_field`,
  `pb_wire` and `pb_free` are gone; `packages/yoloe` is updated with them.
- `pb_skip` takes the `ProtoTag` that was just read instead of a bare wire
  number, and handles groups.

## 0.8.1

Dependency requirements now pin the **major**, matching the rest of the
registry packages:

- `tensor` `^0.4` → `^0`
- `gpukit` `^0.6` → `^0`
- `gpu` `^0.11` → `^0`

A minor release of a dependency is picked up on the next install now,
instead of stranding this package on the minor its requirement happened
to name. That was not hypothetical here: a registry install
resolved `gpukit` to a 0.6 series while the monorepo builds this package
against 0.7 — two different builds of the same commit.

No source change.

## 0.8.0

Everything a torch U²-Net export needs — proven on skyseg.onnx
(map-anything's --mask-sky), max 1.1e-6 against onnxruntime:

- **Host-side INT64 shape folding.** The Shape → Gather/Unsqueeze/
  Concat/Cast/Slice chains a torch export leaves behind now execute on
  the host (they are constants once the input shape is known); a
  host-int tensor lives in the ordinary value map under an RT_HOSTI
  sentinel. Device Gather/Concat/Slice are untouched — the host path
  only claims a node whose data is host-side.
- **Constant nodes.** The embedded TensorProto payload is parsed
  (INT64 values folded into the attribute's ints) instead of warping
  through "unsupported op".
- **Resize: `sizes` input + linear mode.** An explicit sizes input
  (opset ≥ 11, fed by the host chains) wins over float scales, and
  mode=linear runs half-pixel bilinear (pytorch_half_pixel agrees with
  half_pixel at every output size above 1). Nearest + scales behave as
  before.
- **Conv dilations** via gpukit 0.6.3's gkd_conv2d_dil — ignoring the
  attribute silently GREW every dilated map (pad 2, effective kernel
  read as 3) and the failure surfaced three stages later as Concat
  size mismatches.
- **MaxPool ceil_mode** rounds the output size up (U²-Net's 5→3).
- Concat's failure diagnostic now names the node, the input and both
  element counts.
- `gate_dump imgf` — run a model on a real f32 input from a file, for
  oracle comparisons.

## 0.7.3 and earlier

See git history (the package predates this changelog).
