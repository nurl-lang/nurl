# Changelog

All notable changes to NURL — Neural Unified Representation Language —
are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`stdlib/dist/job.nu`: per-kind routing rings (capability domains).**
  `job_set_ring(node, kind, ring)` scopes a task kind to its own consistent-hash
  ring — submit, ownership, and mid-flight forwarding for that kind all resolve
  against the scoped ring, so a task can never land on (or re-home to) a node
  outside its capability domain. Kinds without a scoped ring use the main ring,
  unchanged. New golden coverage in `compiler/tests/dist_job.nu`.
- **`packages/swarm-mcp` v0.5.0 — distributed GPU compute over MCP.**
  Workers started with `--gpu` advertise a capability bit in the HELLO gossip
  (a trailing byte older nodes ignore); every node folds GPU workers into a
  GPU-only ring and the GPU wasm task kind routes on it, so mixed CPU/GPU
  clusters just work. GPU chunks run under the pure-NURL wasmtime with
  `--allow-gpu`, executing CUDA/NVRTC host imports on the worker's real GPU.
  New MCP tool **`compute_submit_cuda`**: the model writes only a CUDA-C
  `__device__ double f(long long x)`; the server generates the complete kernel
  program (NVRTC JIT, grid-stride map, on-device block reduction, host fold),
  compiles it to wasm, and shards it across the GPU workers — verified live on
  an RTX 4090 (π·10⁹ integral; a 250M-element chunk in ~0.3 s including the
  JIT). `compute_submit_kernel` gains `kind:"chunk"` (one kernel call per
  sub-range) and `gpu:true`; `compute_run_wasm` gains `gpu:true`.

### Changed

- **swarm-mcp wasm results are failure-visible.** The wasm result frame is now
  `[ok:1][partial:8]`; a chunk that fails (module trap, missing runtime, GPU
  error) is counted and the task finishes as `status:"error"` with
  `failed_chunks` — never silently folded into the reduce as a zero. Legacy
  8-byte frames are still accepted.

## [0.10.9] — 2026-07-02

A **wasm toolchain** release. The pure-NURL `packages/wasmtime` runtime grows
from a proof-of-concept into a spec-faithful, hostile-input-hardened WebAssembly
engine — real traps and multi-value blocks, bulk memory + reference types, a
bounded explicit frame stack with fuel metering and name-section backtraces, a
much larger WASI surface (positioned I/O, directories, real clocks/entropy/env),
and a CUDA/NVRTC host-import bridge that runs GPU wasm modules on real hardware.
Two compiler FFI argument-coercion fixes make GPU-using NURL compile to wasm at
all, and the runtime now aborts loudly on OOM instead of silently corrupting
wasm32 linear memory. Organisationally, `stdlib/runtime.c` is split into a
bootstrap core and the stdlib FFI shims.

### Added

- **Compile GPU-using NURL to WebAssembly — `nurlc --ffi-host-imports`.** With
  the new flag, external `` `&`-FFI `` libraries are satisfied by the run-time
  embedder as wasm imports (module `env`) instead of a native link line, and the
  build-time `stdlib/runtime.<lib>` sentinel gate is skipped (native path
  unchanged, flag off by default). `nurlapi`'s wasm build passes it through and
  links with `-Wl,--allow-undefined`, so undefined FFI symbols become wasm
  imports; a genuinely missing symbol traps at run time with its name. This is
  what lets a GPU package (objdet → onnx → gpu) compile to a wasm module the host
  resolves against real libcuda/libnvrtc.
- **`packages/wasmtime` — WASI expansion.** `environ_get`/`_sizes_get` from
  repeatable `--env NAME=VALUE` (capability-style; the host environment is never
  inherited implicitly); real `clock_time_get` (wall + monotonic, ns) and
  `random_get` from the OS CSPRNG (both previously returned zeros); a `path_open`
  overhaul (directory fds, `O_CREAT`/`O_EXCL`/`O_APPEND`/`O_TRUNC` semantics),
  positioned `fd_pread`/`fd_pwrite`/`fd_tell`/`fd_sync`, offset-correct
  `fd_write`, a directory surface (`fd_readdir`, `path_create_directory`,
  `path_remove_directory`, `path_unlink_file`, `path_rename`,
  `path_filestat_get`), and multiple preopens via repeatable `--dir`.
- **`packages/wasmtime` — bulk memory + reference types.** Passive data/element
  segments (`memory.init`/`data.drop`, `table.init`/`elem.drop`), a runtime
  funcref table mutable via `table.get`/`set`/`grow`/`size`/`fill`/`copy`,
  `ref.null`/`ref.is_null`/`ref.func` and typed `select`, and up-front
  bounds-checked `memory.copy`/`fill`/`init` (no partial writes before a trap).
- **`packages/wasmtime` — explicit frame stack, fuel metering, backtraces.**
  `exec_func` drives an explicit frame stack, so guest calls no longer recurse on
  the host native stack — deep guest recursion is bounded by `max_depth` (65536
  frames, trap `call stack exhausted`) instead of a host stack overflow (verified
  1M-deep). Optional `--fuel N` traps a runaway guest after N instructions; the
  custom `name` section is decoded and traps append a wasm backtrace.
- **`packages/wasmtime` — CUDA/NVRTC GPU host-import bridge.** Resolves a GPU wasm
  module's `cuda`/`nvrtc` imports to real libcuda/libnvrtc, marshalling guest
  linear memory ↔ host (every `*u` param is a guest offset → host address;
  opaque handles and `CUdeviceptr` travel as raw `i64`; `cuLaunchKernel`'s guest
  `void**` is reconstructed host-side). `nurl.sh` auto-links libcuda/libnvrtc
  when those symbols appear and stubs them on a GPU-less host. Verified on an
  RTX 4090 (`vadd`, `cuInit`+`cuDeviceGetCount`).
- **`nurlapi` — `/build_wasm` accepts pre-compiled IR (`ir` field).** The only
  way to wasm-build a multi-file package: a host `nurlc` resolves the `$`-imports
  the container lacks and the container just does the wasm rewrite + wasi-clang
  link.

### Changed

- **Runtime source split (A9) — `stdlib/runtime.c` → bootstrap core + FFI
  shims.** The 5.2k-line runtime is separated into
  `stdlib/runtime_core.c` (bootstrap core: OOM policy, version, Win32
  shims, basic stdio I/O, string ops, file/dir, the allocator +
  panic-unwind journal, IEEE-754/math, and panic/recover) and
  `stdlib/runtime_ffi.c` (stdlib FFI shims: HTTP, process, TCP/TLS + UDP
  sockets, DNS, thread trampolines, signals, and the async fiber runtime +
  I/O reactor). `stdlib/runtime.c` becomes a thin aggregator that
  `#include`s both into one translation unit, so the default build still
  emits a single `stdlib/runtime.o` with a byte-identical symbol set and
  link surface — no build-script or bootstrap changes. `runtime_core.c`
  has zero references into the FFI half and compiles standalone, so it
  now *defines the core symbol set* a bootstrap/`no_std` target must
  provide (unblocks ROADMAP D2). Organisational only: no behavioural
  change, self-host fixed point held, full corpus + sanitizer suite green.
- **`packages/wasmtime` — core semantics: multi-value, real traps, checked
  `call_indirect`.** Block types decode as signed-LEB `s33` (multi-value
  blocks/loops/ifs), `call_indirect` performs the runtime structural signature
  check, the `start` section runs at instantiation, integer divide-by-zero and
  `INT_MIN/-1` overflow trap, float→int truncation traps on NaN / out-of-range
  (with saturating `0xfc` forms), and float min/max/compare are NaN-correct.
- **`packages/wasmtime` — import layer strictness.** Imports record their module
  name and dispatch verifies `wasi_snapshot_preview1`; a table/memory/global
  import (or `global.get` in a const expression) is now a hard decode error
  instead of being silently skipped.
- **`packages/wasmtime` — hardened against hostile input (v0.6.0).** Audited
  against malformed/adversarial wasm (ASan-fuzz + exhaustive prefix sweep): every
  vector count is validated against the bytes physically remaining before
  allocating (`__chk_count`), negative/over-long section and name-subsection
  sizes are rejected, truncated init/element expressions are clean decode errors,
  and `mem.min`/`table.min`/per-function locals are capped. Every input is now
  memory-safe and terminating; valid modules still run byte-identically to
  reference wasmtime.

### Fixed

- **`nurlc` — FFI argument coercion to the declared parameter width, plus
  int↔pointer.** An integer argument whose width differs from an FFI function's
  declared parameter (NURL literals are `i64` → an `i32` param) was emitted
  verbatim; native LLVM tolerates it but `wasm-ld` replaces the whole function
  with an `unreachable` stub that traps at run time. `gen_ffi_decl` now records
  each symbol's LLVM parameter types (`__ffi_params`) and `gen_call` coerces via
  `trunc`/`sext` (and `inttoptr` for a bare `0`/handle passed to a pointer
  param). `__ffi_params` is also registered in the `scan_fn_sigs` pre-pass so
  forward-referenced FFI symbols coerce correctly. Fixes the long-standing
  `fread`/`cuLaunchKernel` "unreachable stub" on wasm.
- **runtime — abort loudly on OOM, on every allocation.** `nurl_alloc`/`_zalloc`/
  `_realloc` and the 81 other `malloc`/`calloc`/`realloc`/`strdup` sites in the
  runtime returned raw NULL on OOM. On native that faults on first write, but on
  wasm32 address 0 is ordinary writable linear memory, so a NULL-backed
  string/vec silently corrupts state (observed as the `nurlc.wasm` self-host
  "hang": once `memory.grow` failed past the 4 GiB ceiling the analysis spun on
  NULL-backed state). File-wide checked wrappers now abort with
  `nurl: out of memory (requested N bytes)`; the panic-journal grow keeps its
  deliberate degrade-to-a-leak.
- **FFI decls — `nurl_peek_i32`/`nurl_poke_i32` are 32-bit, not `i64`.** Every
  package declared these 32-bit runtime accessors with NURL's `i` (`i64`); on
  LP64 native the register hid the high bits, but on wasm the type differs from
  `runtime.wasm.o` and `wasm-ld` emits an `unreachable` stub. Fixed to `i32` in
  gpu (`cuda.nu`/`cpu.nu`), onnx (`pb.nu`) and yoloe.
- **`nurlapi` — libc `off_t`/`size_t` wasm width shims.** Correct the FFI shim
  widths that produced `unreachable` stubs on `fs.nu`'s `fopen`/`fread` file path
  (`lseek` removed from the shim list — its `off_t` is already 64-bit on wasm32;
  a new `w` param-char for an `i32` parameter `nurlc` already emits as `i32`).

## [0.10.8] — 2026-07-02

A **dynamic trait objects** release. NURL's trait system gains a second,
opt-in dispatch path alongside the existing static one: `%Trait` boxes a
concrete implementer behind a vtable fat pointer, so heterogeneous
collections and plugin-style APIs can dispatch on the trait rather than the
concrete type — no GC, and the existing monomorphised `impl` dispatch is
unchanged. Diamond supertraits upcast through the same object, object safety
is checked at compile time, and the box's `Drop` is synthesized so the
single-owner memory model holds. A real leak in the (unrelated) static
impl-method dispatch path, found while adding the feature, is fixed
alongside it.

### Added

- **Dynamic trait objects — `%Trait` (docs/spec.md §4.9).** A trait can now be
  used as a runtime-dispatched *object* so values of different concrete types are
  handled uniformly, layered *beside* the existing static path (a concrete
  `( fmt p )` still lowers to `fmt__Point`; concrete values carry no trait
  identity). `%Trait` is a fat pointer `%dyn.<Trait> = { i8* data, i8* vtable }`:
  a heap-boxed copy of the value plus a per-impl vtable (slot 0 = destructor,
  slots 1..K = one uniform-ABI thunk per method). `( dyn Trait value )` boxes a
  value that implements `Trait`; a bare-name call `( method obj )` on a `%Trait`
  receiver loads the vtable slot and dispatches indirectly. **Diamond upcasting**:
  the vtable flattens the transitive supertrait method set, so a `%Pet` object
  (`Pet : Animal`) dispatches Animal's methods too — including inherited
  **default** methods, which call back through the object's own dynamic dispatch.
  **Object safety** is enforced with a precise diagnostic: a trait is usable as
  `%Trait` only if every method (and every supertrait's) is dispatchable from an
  `i8*` self plus its signature (has a `[T]` Self parameter; no method lacks a
  Self receiver, names Self beyond the receiver, consumes self by value, or
  mentions an associated type). **Memory safety**: a `%Trait` binding is an owned
  value with a synthesized `Drop` that runs the vtable's slot-0 destructor on the
  boxed value (freeing its owned resources transitively) then frees the box — no
  leak, no double-free, verified under AddressSanitizer. Tests: `dyn_dispatch`,
  `dyn_diamond`, `should_fail_dyn_not_object_safe`.
- **`nurlfmt` understands `%Trait` type sigils.** The formatter now distinguishes
  the three uses of `%` — trait/impl declaration sigil, `%Trait` object type, and
  the modulo operator — using prefix-notation context (an operand never precedes
  an operator). A `%Trait` in a signature, binding, or return type glues to the
  trait name (`%Pet`) and no longer opens a spurious top-level declaration that
  split the signature across lines.
- **`nurl_free_count()` runtime primitive.** A symmetric companion to
  `nurl_alloc_count()` (counts every `nurl_free` of a non-NULL pointer), so a
  program can bracket a scope and assert leak-freedom deterministically without a
  sanitizer. Used by the new `trait_owned_ret_no_leak` regression test.

### Fixed

- **Owned-string temporaries from trait-method calls leaked.** A trait method
  returning an owned `s` (e.g. via `nurl_str_cat`) whose result was passed
  straight to another call — `( nurl_print ( label d ) )` — leaked the temporary;
  plain-function composition already freed it. The impl-method dispatch path
  (Group F in `gen_call`) emitted its call and returned **without publishing any
  of the `__last_call_*` return side-channels** the caller reads, so the callee's
  owned-string / borrow / signedness / `??`-propagation markers were all lost —
  not just a leak but a latent borrow double-free and a `u`/`!T E` mis-handling.
  Fixed by factoring the marker propagation into one helper
  (`mem_propagate_call_ret_markers`) shared by both the impl-method and
  regular-call paths, so no dispatch path can silently omit a marker.

## [0.10.7] — 2026-07-01

A **CPU inference + GUI** release. The GPU/ML stack from 0.10.6 gains two big
things: models now run **with no GPU at all** (a CPU backend in `packages/gpu`
that runs the same CUDA-C kernels on the host), and the `yoloe` webcam demo can
draw its live segmentation into a **real X11 window** — or the terminal.

### Added

- **CPU backend for `packages/gpu` (0.1.0 → 0.2.0).** `gpu_open` uses CUDA when
  a device is present and otherwise falls back to a CPU backend that runs the
  *same* CUDA-C kernels on the host: each kernel is wrapped in a small
  CUDA-compatibility shim (`blockIdx`/`threadIdx`/`blockDim`/`gridDim` as
  thread-locals, `__global__` etc. as no-op macros) plus a generated grid-loop,
  compiled by the system C++ compiler, `dlopen`'d, and run with **OpenMP**
  across cores. `gpu_launch`'s `void**` argument array is byte-for-byte what
  CUDA passes, so the neutral surface is unchanged and every caller (`onnx`,
  `objdet`, `yoloe`) gets the fallback for free. `NURL_GPU=cpu` forces it.
  Verified identical CPU vs GPU on the onnx MLP and the full 267-node YOLOE-seg
  forward.
- **Driverless linking.** A program that references `packages/gpu` no longer
  hard-requires libcuda/libnvrtc to load: `nurl.sh` links small stub objects
  (`stdlib/{cuda,nvrtc}_stubs.o`, built by `build.sh`) in place of `-lcuda` /
  `-lnvrtc` when those libraries are absent — the binary links, loads, and
  auto-falls-back to the CPU backend. `NURL_GPU_STUBS=1` forces the stubs to
  build a portable CPU-only binary on a GPU host. `runtime.c` gains one tiny
  generic thunk, `nurl_cpu_launch`, so the backend can call the `dlsym`'d
  kernel entry.
- **X11 GUI-window support.** `build.sh` writes a `runtime.X11` sentinel when
  libX11 is present and `nurl.sh` auto-links `-lX11` only when `@XOpenDisplay`
  appears — the same opt-in-by-symbol pattern as libcuda/libopus, so headless
  programs are unaffected. Used by `packages/yoloe`'s new window preview.
- **`yoloe` — a real webcam segmentation tool.** The `yoloe` command is now a
  flag-driven, self-documenting CLI with three sub-commands — `detect`, `seg`,
  and `cam` — and `cam` shows the **live** segmented feed either in a **real
  X11 window** (full webcam resolution, pure NURL via libX11) or in the
  terminal (area-averaged 24-bit half-blocks, works over SSH). `--boxes` /
  `--mask` pick what to draw, `--frames` bounds the run (omit ⇒ until Ctrl-C),
  `--out` saves frames, `--device` / `--gpu` select the camera / CUDA device.

### Fixed

- **`nurlpkg` `{ path, version }` hybrid dependencies** are published + resolved
  correctly end-to-end (carried over from 0.10.6); the `gpu`/`onnx`/`yoloe`
  packages were republished with the correct dependency edges so a registry
  install resolves the whole chain.

## [0.10.6] — 2026-06-30

A **GPU compute + ML inference** release. NURL gains the ability to run real
neural networks — CNNs, vision-language transformers, and end-to-end object
detection *and instance segmentation* — entirely in pure NURL on the GPU,
through a new stack of registry packages (`gpu` → `onnx` → `objdet` /
`yoloe`). The crown jewel is `yoloe`: promptable open-vocabulary detection
with per-object masks, **live off a webcam**, captured in pure NURL via
Video4Linux2 — no ffmpeg, no OpenCV, no external inference engine. The
toolchain changes here are the thin layer that makes that possible plus a
`nurlpkg` dependency-resolution fix; the heavy lifting lives in the packages.

### Added

- **Typed 4-byte buffer accessors in the runtime.** `stdlib/runtime.c` gains
  `nurl_peek_i32` / `nurl_poke_i32` / `nurl_peek_f32` / `nurl_poke_f32` —
  natural-stride reads/writes for the packed `float32` / `int32` arrays that
  GPU kernels, image data, and binary wire formats use (the 8-byte
  `nurl_peek`/`poke` can't address a 4-byte array at its stride). Pure and
  dependency-free; they ship to every target, no GPU required.
- **Automatic GPU linking, opt-in by symbol.** `nurl.sh` and `build.sh` now
  link `-lcuda` / `-lnvrtc` **only** when a program references `cu*` / `nvrtc*`
  symbols (detected via sentinels). A GPU-less host — or any program that
  never touches the `gpu` package — is completely unaffected; the CUDA
  dependency lives entirely in `packages/gpu`.
- **New registry packages — a pure-NURL GPU/ML stack:**
  - **`gpu` 0.1.0** — backend-neutral GPU compute (`Gpu` / `GpuKernel` /
    `GpuBuffer`: open, compile, alloc, upload/download, launch, sync). One
    backend: CUDA, with kernels written in CUDA-C and compiled to PTX at
    runtime via NVRTC, run over the CUDA Driver API — all bound from pure
    NURL with no `runtime.c` bridge.
  - **`onnx` 0.1.0 → 0.4.0** — run ONNX models on the GPU: a pure-NURL
    protobuf decoder (no protoc) builds an in-memory graph, and a
    GPU-resident executor dispatches each operator to a CUDA-C kernel. Grew
    from MLPs (`Gemm`/`Relu`) to CNNs (`Conv`/`MaxPool`/`BatchNormalization`/
    `LeakyRelu`/N-D tensors) to the transformer set (`LayerNormalization`/
    `Erf`/`Gather`/batched `MatMul`/N-D `Transpose`/`Softmax`) to the
    **segmentation mask-prototype branch** — a new `ConvTranspose` op plus a
    model's second graph output reachable via `rt_output1`. Verified
    end-to-end against onnxruntime at every step.
  - **`objdet` 0.1.0 / 0.2.0** — object detection (tiny-yolov2) from pure
    NURL on the GPU: image I/O, YOLO decode, NMS; matches onnxruntime
    pixel-for-pixel and supports a frame-sequence video mode.
  - **`yoloe` 0.1.0 / 0.2.0** — promptable open-vocabulary detection **and
    instance segmentation**, a NURL port of YOLOE (ICCV 2025). Names the
    classes you want at runtime; the whole YOLOv8/YOLOE network (backbone,
    neck, DFL head, region-text contrastive head) runs on the GPU. The
    MobileCLIP text path is pure NURL too — a 12-layer CLIP text transformer
    (bit-exact vs onnxruntime) and a CLIP byte-level BPE tokenizer
    (byte-identical to open_clip). 0.2.0 adds **per-object masks** and a
    pure-NURL **Video4Linux2** capture path (`open`/`ioctl`/`mmap`, YUYV→RGB)
    for **live segmentation off a webcam** — no ffmpeg, no OpenCV.
  - **`swarm-mcp` 0.3.0 / 0.4.0** — a unified node with composable,
    non-exclusive roles (`--relay` / `--worker` / `--mcp`), `--token`
    cluster security (group-id + HMAC), MCP served over HTTPS JSON-RPC, and
    floating-point (`f64`) distributed compute kernels.
- **Registry renders package READMEs.** The registry Worker now turns a
  published package's README into HTML (Markdown → HTML in TypeScript,
  XSS-safe), including images served straight from the package tarball.

### Fixed

- **`nurlpkg` resolves `{ path, version }` hybrid dependencies correctly.** A
  Cargo-style hybrid dep (a local `path` override that also carries a
  registry `version`) is now (a) **published** with its `version` in the
  registry index — so a downstream consumer can resolve it — and (b)
  **installed** by falling back to the registry version when the local path
  is absent, resolved transitively across the whole dependency tree. Before
  this, publishing such a package dropped the dependency from the index and a
  registry `install` of it silently skipped the dep. This is what lets the
  layered `gpu` ← `onnx` ← `yoloe` packages install from the registry.
- **`onnx` text-encoder forward correctness.** Three real runtime bugs —
  `Softmax` with a negative axis, `Add` mask broadcasting, and an `Engine`
  value-map that wasn't reset between runs — were producing all-`NaN`
  outputs hidden by a NaN-blind comparison. Fixed; the MobileCLIP text
  encoder now matches PyTorch to ~5e-6.
- **Registry README links.** Links that wrap across source lines, and
  monorepo sibling-package references, now render correctly.

## [0.10.5] — 2026-06-29

A **compiler correctness** release: a single codegen fix that stops the
toolchain from overflowing the stack on hot loops.

### Fixed

- **`nurlc` now emits every `alloca` in the function entry block.**
  Previously each `:` binding's stack slot was allocated at its lexical
  position, so a binding inside a loop re-allocated a fresh slot on every
  iteration (LLVM only reclaims allocas at `ret`) — a loop over N items
  leaked N stack slots and eventually overflowed the stack. clang's
  `mem2reg` promoted those slots away and hid the leak, but the released
  toolchain (relinked with the bundled `zig cc -O2 -flto` for
  portability) kept the per-iteration stack growth and crashed. The most
  visible symptom was `nurlpkg publish` segfaulting inside the pure-NURL
  gzip/deflate path while packing a multi-kilobyte tarball. All NURL
  allocas are static-size, so hoisting them to the entry block is the
  canonical LLVM idiom and semantically identical — the slot lifetime is
  already function-wide; the compiler just stops re-issuing it per
  iteration. The bootstrap snapshot (`nurlc_lastgood.{nu,ll}`) was
  refreshed accordingly.

## [0.10.4] — 2026-06-29

A **WebAssembly + self-hosting** release. NURL gains a from-scratch WebAssembly
runtime written entirely in NURL, the compiler now **self-hosts on wasm** — the
compiler compiled to `wasm32-wasi` recompiles its own source to byte-identical
IR — and the `swarm-mcp` engine can compile arbitrary NURL kernels to wasm and
run them across the cluster.

### Added

- **`packages/wasmtime` — a WebAssembly runtime written in pure NURL.** No
  libwasm, no embedded interpreter, no external `wasmtime` binary: it decodes a
  wasm binary (LEB128, every standard section) and interprets the full integer +
  float instruction set — structured control flow (`block`/`loop`/`if`/`else`/
  `br`/`br_if`/`br_table`/`return`), `i32`/`i64` arithmetic / comparison /
  bitwise ops (signed **and** unsigned, rotates, `clz`/`ctz`/`popcnt`,
  sign-extension), `f32`/`f64` ops and every int↔float conversion, linear memory
  (load/store, `memory.size`/`grow`, bulk `memory.copy`/`fill`, the data
  section), globals, tables + `call_indirect`, and the element section. It hosts
  real `wasm32-wasi` command modules via the WASI snapshot-preview1 surface
  (`proc_exit`, `fd_write`, `args_*`/`environ_*`, `clock_time_get`,
  `random_get`) plus a file-descriptor table with **`--dir` preopen** and file
  ops (`path_open`/`fd_read`/`fd_seek`/`fd_write`/`fd_close`/`fd_filestat_get`),
  so a module can read host files. Cross-checked byte-for-byte against the
  reference `wasmtime` and ASan-clean; floats held as IEEE-754 bits via
  `std/floatbits`.
- **NURL self-hosts on WebAssembly.** The compiler compiled to `wasm32-wasi`
  (`nurlc.wasm`) compiles NURL source — up to and including the full compiler
  `nurlc.nu` itself — to IR **byte-identical to the native `nurlc`**, under both
  the reference `wasmtime` and the pure-NURL `packages/wasmtime` runtime above
  (the 2.4 MB / 65530-line self-compile is md5-verified). The borrow-checker
  analysis is skipped for the wasm self-compile (`--no-borrowck`); it emits no
  IR, so the output is identical. Reaching this required the three `wasm32` ABI
  fixes listed under *Fixed*.
- **`packages/swarm-mcp` — an MCP-driven distributed compute engine.** A model
  sets a workload over MCP and the cluster map-reduces it. Two kernel forms:
  `compute_submit` takes a small integer-expression kernel (in `x`, over a
  range, with a `sum`/`product`/`min`/`max`/`count` reduce); `compute_submit_kernel`
  takes an arbitrary **per-element NURL kernel** (`@ kernel i x → i { … }` plus
  any imports/helpers — no `main` needed), which the server wraps into a full
  program, compiles to wasm via the build service, and shards across the live
  workers. `compute_run_wasm` runs an already-compiled `wasm32-wasi` module.
  Tools: `compute_submit` / `compute_submit_kernel` / `compute_run_wasm` /
  `compute_list` / `compute_result`.
- **`packages/swarm` 0.2.0 — real distributed compute workloads.** The
  install-to-join cluster now runs genuine sharded workloads (e.g. prime
  counting and sum-of-squares) across the ring via `dist/job` — `π(10⁶)=78498`
  computed across four workers — not just a membership demo.
- **`std/floatbits` — IEEE-754 bit reinterpretation + binary float I/O.** NURL's
  `#` cast converts a float's *value*; this new module reinterprets its *bit
  pattern* — the operation binary formats need, and previously impossible in the
  stdlib (`bytes_push_float` only writes `%g` text). Backed by a zero-allocation
  runtime bitcast (`memcpy`, correct for NaN/±Inf/subnormals): `f64_to_bits` /
  `bits_to_f64`, `f32_to_bits` / `bits_to_f32`, and explicit-endian binary
  helpers `bytes_push_f64_le/_be` · `bytes_read_f64_le/_be → ?f` (and `f32`
  variants). For serialization (msgpack/protobuf/wasm/audio), float hashing,
  random→float, and the pure-NURL wasm runtime. KAT-tested (`floatbits`).

### Changed

- **`net/relay` frame limit raised from 128 KiB to 16 MiB.** A relayed message
  may now be up to 16 MiB, large enough to forward a compiled wasm compute
  kernel (a NURL→wasm module bundles the runtime, ~250 KB–1 MB) in one frame.
  It is only an upper bound, so small gossip / audio / unicast frames are
  unaffected.

### Fixed

- **Field store into a struct pointer silently miscompiled when the value name
  was a non-parameter local shadowing the field.** `= . t lo lo`, where `lo` is
  an in-scope local that also names a field of `t`'s struct, compiled to a
  value-as-index array store (`t[lo] = lo`, `getelementptr %T, %T* t, i64 %lo`)
  — an out-of-bounds, struct-corrupting write with no diagnostic. The read path
  already let a concrete struct field always win over a same-named variable;
  the store path only did so when the name was a *parameter*. The two are now
  symmetric: a name that is a field of the (non-generic) struct stores into that
  field whether it is a parameter or a local. The value-as-index array store is
  still taken when the name is not a field of the struct — raw pointers, and the
  tparam element types `stdlib/core/vec.nu` writes through (unaffected;
  full bootstrap + corpus green). Regression test `field_store_shadow`.
- **`nurlc.wasm` trapped on the first token compiled — `int`-returning libc
  shim ABI.** The `wasm32` build's shim layer widened every non-pointer libc
  return to `i64`, correct for `size_t` (which `nurlc` declares `i64`) but wrong
  for `int` (`strcmp`/`memcmp`/`atoi`/…, which `nurlc` declares `i32`): a
  `call i32 @__nurl_<fn>_shim` against a `define i64` shim is a wasm
  signature mismatch, so `wasm-ld` replaced the call with a trap stub and the
  compiled `nurlc` trapped on its first `strcmp` (the first lexed token). The
  shim now returns `i32` for `int`-returning functions.
- **`__tok_write` passed a token pointer as `i64` to an `i8*` parameter.** The
  lexer cast each strdup'd token spelling to `# i` (i64) for `__tok_write`'s
  `s` (i8\*) `val` parameter — a no-op on 64-bit, but on `wasm32` (4-byte
  pointers) an `i64`-for-`i8*` signature mismatch that trapped on the first
  token. The spurious cast is removed (the value is a string; `__tok_write`
  already narrows it internally).
- **`wasm32` link dropped functions referenced only through the call-table.**
  NURL closures take function addresses, which become wasm function-table
  indices; `wasm-ld`'s default `--gc-sections` pruned/renumbered the table so a
  stored `call_indirect` index no longer mapped to its function — fine for small
  programs, but `nurlc.wasm` compiling a >150-function program trapped
  (`call_indirect: index out of range`). The wasm link now passes
  `-Wl,--no-gc-sections` to keep the table stable.

## [0.10.3] — 2026-06-28

A **portability + distributed-stack** release. The runtime drops its last
glibc-version-specific symbols so the toolchain builds and links on older-glibc
targets again (notably **Raspberry Pi OS aarch64**), a silent `net/relay`
group-multicast bug is fixed, and the new **`packages/swarm`** package turns the
distributed stack into a compute cluster you join by installing it.

### Fixed

- **Runtime failed to link on older-glibc targets (e.g. Raspberry Pi OS
  aarch64): `undefined symbol: __isoc23_strtoul` / `__isoc23_strtol`.** When the
  runtime is compiled with glibc ≥ 2.38 headers in C23 mode, `strtoul` /
  `strtol` / `atoi` / `scanf` resolve to the versioned symbols
  `__isoc23_strtoul` etc., which are baked into the shipped LTO runtime bitcode
  and then undefined when linked against a target with an older glibc. The
  runtime no longer calls any of them: a hand-rolled decimal parser
  (`nurl__parse_ul`) replaces `strtoul`/`atoi`, and `nurl_read_int` is rebuilt
  on `getchar`/`ungetc` instead of `scanf`. The runtime bitcode now references
  none of the `__isoc23_*` symbols, so it links cleanly across every glibc/musl
  version and target (verified by cross-linking for aarch64 against glibc 2.28).
- **`net/relay` group multicast silently dropped any non-32-byte group id.**
  `GJOIN`/`GLEAVE` carried the group id as a raw, variable-length body, but
  `GSEND` reused the fixed 32-byte pubkey split — so a group id that was not
  exactly 32 bytes was mis-parsed on the server (aliasing the payload) and the
  fanout was silently skipped. Group sends are now length-delimited
  (`[gidlen:2][gid][payload]`) via `relay_gsend_gid` / `relay_gsend_payload`, so
  a group id of any length round-trips. Regression test added in
  `relay_codec` (a 5-byte gid). Existing 32-byte users (`replicated_counter`,
  `pttvoice`) are unaffected.

### Added

- **`net/relay` server verbose mode.** `relay_server_set_verbose(rs, 1)` (and a
  new `RelayServer.verbose` field) logs each peer connect/disconnect as
  `relay: + peer <id>` / `relay: - peer <id>`. `packages/swarm`'s relay exposes
  it as `swarm relay <host> <port> --v` / `--verbose`, so cluster membership is
  visible as workers come and go.
- **`packages/swarm` — a distributed compute cluster you join by installing it.**
  `nurlpkg install swarm` then `swarm worker <relay> <port>` makes a machine a
  live compute node: it announces itself over the relay group (HELLO census),
  every node folds it into the consistent-hash ring, and it takes its share of
  work. `swarm submit … primes <lo> <hi>` / `sumsq <lo> <hi>` shards a real
  numeric workload across the live workers (by key, via `dist/ring` + `dist/job`)
  and sums the partial results — verified live (π(10⁶) = 78498) and by an
  ASan-clean offline suite that pins exact sharding.

## [0.10.2] — 2026-06-28

A **language-maturity** release. The static trait system reaches v1.0
(coherence, supertraits, associated types, a dyn-dispatch seam); `Result` gains
a by-value representation; the toolchain gains first-class **FreeBSD** support
(now a CI gate) and a local **MCP server** that exposes the compiler to LLM
agents. The standard library absorbs argument parsing, letting the registry
shed its `argz` and `tls` packages.

### Added

- **Trait system v1.0.** Sound bare-name method dispatch (coherence:
  `method##type` registered once, position-idempotent re-scan, `i`/`i64`
  collisions resolved); **supertraits** (`% Sub : Super`, whole-program-enforced
  and transitive); **associated types** (`type Item` in a trait, bound per impl
  and substituted into defaults); and a recorded **dyn-dispatch vtable seam**.
  Documented in spec §4.9 and the EBNF.
- **`std/utf8` — a validating UTF-8 codepoint layer** over NURL's byte strings
  (rejects overlong / surrogate / out-of-range encodings, with U+FFFD recovery):
  `utf8_valid` / `utf8_len` / `utf8_nth` / `codepoints` / `encode_cp` /
  `utf8_substr` / … The byte-level `core/string` stays the fast default; the
  codepoint layer is opt-in.
- **Send check.** Capturing a non-atomic `Rc` in a `thread_spawn` closure is now
  a **compile error** (use `Arc`), catching that data race at compile time.
- **`nurl-mcp` — a local MCP server for the toolchain** (registry package:
  `nurlpkg install nurl-mcp`). Exposes the *locally installed* compiler to an
  LLM agent over the Model Context Protocol so it can build / run / type-check /
  format NURL against the host's real files and read the installed stdlib. Stdio
  by default; an optional **token-authenticated HTTP** transport gates code
  execution behind `--allow-run` and refuses a non-loopback bind without
  `--token`. The LLM-facing counterpart of `nurl-lsp`.
- **FreeBSD support.** Documented as a first-class **host platform** (the
  toolchain binaries are libc-only and the wrappers POSIX `sh`); CI now builds,
  bootstraps, and runs the full test corpus on a real **FreeBSD 14 VM** as a
  hard gate. `docs/PLATFORMS.md` is split into codegen targets vs. host
  platforms, and `docs/BUILDING.md` documents every CI gate.

### Changed

- **`Result` `!T E` now lowers to `{ i1, T, E }`.** The Ok payload rides field 1
  and the Err payload field 2, both **by value**, mirroring `?T` → `{ i1, T }`.
  A multi-field-struct success payload is no longer heap-boxed — the Ok path
  emits no `nurl_alloc`. Note: direct numeric access to the *error* payload
  moves from `. r 1` to `. r 2` (`??` / `\` matching constructs are unaffected).
- **Argument parsing is now a stdlib facility, `std/args`** (flags, value
  options, clustered shorts, `--`, positionals, an auto-generated `--help`); the
  registry CLIs (`nq`, `md2html`, `chart`, `iforest`) migrated onto it.
- **`install-toolchain` now installs `nurlfmt`**, and its sourceable `env` file
  is POSIX-`sh`-safe — the old `${BASH_SOURCE[0]}` form aborted FreeBSD / Alpine
  `/bin/sh` with "Bad substitution". The release relinks `nurlfmt` against the
  old-glibc floor like the other shipped binaries.

### Removed

- The **`tls`** registry package — pure-NURL TLS now lives in the stdlib, and
  `psql` / `redis` depend on it directly.
- The **`argz`** and **`argz-demo`** packages — argument parsing is now
  `std/args`.

## [0.10.1] — 2026-06-27

A **security-hardening** release for the pure-NURL cryptography and TLS stack
introduced in 0.10.0. A full adversarial audit of the OpenSSL-replacement code
(documented in the new `docs/CRYPTO.md`) drove fixes across certificate-chain
validation, the TLS 1.3 protocol guards, and the side-channel posture of every
asymmetric and symmetric primitive. The elliptic-curve secret path is now
**constant-time including operand timing** via a dedicated fixed-limb P-256
field, and the certificate chain now enforces Basic Constraints — closing an
"any leaf certificate can sign for any host" authentication bypass.

### Security

- **Certificate-chain policy hardened (X.509).** The chain now enforces
  BasicConstraints `cA:TRUE` on every signing certificate — closing a complete
  authentication bypass where any leaf certificate could mint a forged cert for
  any host (the classic Moxie Marlinspike break; `is_ca` was parsed but never
  read, and was in fact written to a by-value copy and discarded). Adds
  keyUsage `keyCertSign` / EKU `serverAuth` enforcement, `pathLenConstraint`,
  embedded-NUL dNSName rejection, tightened wildcard matching (`*.com` /
  `*foo.com` now rejected), iPAddress-SAN matching, a ≥2048-bit RSA-key floor,
  a presented-chain length cap, and issuer/subject DN name-chaining.
- **TLS 1.3 protocol guards.** Reject an all-zero X25519 / P-256 ECDHE shared
  secret (RFC 8446 §7.4.2) on both client and server; check the §4.1.3
  downgrade sentinel when a 1.3-capable client negotiates 1.2; fail closed on a
  CSPRNG failure; constant-time TLS 1.2 server-Finished comparison.
- **Constant-time symmetric primitives.** AES computes its S-box in constant
  time (`Affine(x⁻¹ in GF(2⁸))`, no secret-indexed table — closing the
  cache-timing key-recovery leak); GHASH is branchless; the GCM and
  ChaCha20-Poly1305 entry points validate key/nonce lengths and enforce
  plaintext caps. Tag comparisons were already constant-time.
- **Constant-time asymmetric primitives.** `bigint_modpow` is now a Montgomery
  powering ladder with a uniform square-multiply trace independent of the
  secret exponent. The P-256 secret scalar multiply (ECDSA nonce, ECDHE) runs
  on a new dedicated **fixed-limb constant-time GF(p256) field**
  (`std/p256_field`), so it is constant-time *including operand timing*. RSA
  private-key signing adds base blinding (plus a signature range check and the
  PSS maskedDB check). Ed25519 verify rejects non-canonical encodings and
  `S ≥ L` (malleability); ECDSA verify and P-256 ECDH validate that peer
  points are on-curve (invalid-curve guard).
- **Side-channel scope, stated honestly** (`docs/CRYPTO.md`): on the
  timing/cache axis the EC and symmetric primitives are constant-time including
  operand timing, and RSA's residual operand timing is covered by base
  blinding. Physical **power/EM (DPA/template) side-channels are out of scope**
  for any pure-software stack. Revocation (OCSP/CRL) and X.509 name constraints
  are not checked.

### Added

- **`std/p256_field.nu`** — a dedicated fixed-16-limb constant-time GF(p256)
  field (Montgomery CIOS multiply, conditional-±p add/sub, Fermat inverse) and
  constant-time P-256 point arithmetic via the Renes–Costello–Batina complete
  addition formula. Cross-checked against the bigint reference (2000 cases) and
  Python `cryptography` (500/300 cases); new corpus test `p256_ct_field`.
- **`docs/CRYPTO.md`** — documents the pure-NURL crypto/TLS stack: implemented
  primitives, the side-channel taxonomy, TLS 1.3 controls, X.509 verification,
  and the soundness contract. Linked from the README.
- `bigint_modinv` (modular inverse) and `bigint_cselect` (constant-time select)
  in `std/bigint.nu`.

### Changed

- `tls_accept_rsa` now takes the RSA public exponent (argument order `n e d`)
  so the server's CertificateVerify signature can be base-blinded; `net.nu`'s
  TLS listener threads the exponent through. Other public TLS APIs are
  unchanged.

### Fixed

- The CHANGELOG's DEFLATE interop claim is now "round-trip / KAT verified"
  rather than "byte-for-byte" — a greedy LZ77 encoder produces a valid but not
  bit-identical stream versus zlib.

## [0.10.0] — 2026-06-26

The **self-sufficiency** release. NURL no longer depends on any third-party
C library at its core: the entire external-library surface — `libcurl`,
`libssl`/`libcrypto`, `libpq`, and `libz` — has been removed from the
runtime and replaced with pure-NURL implementations in the standard library.
A default `./build.sh` now links **`libc` only** (plus `libm`). The same
self-contained stdlib provides TLS 1.3 (client *and* server), cryptography,
HTTP/1.1, and DEFLATE/gzip/zlib — written in NURL, verified against the
libraries they replace by known-answer vectors and round-trip interop (our
DEFLATE output is a valid, if not byte-identical, stream — a greedy LZ77
encoder compresses differently from zlib), and clean under AddressSanitizer.

Alongside the dependency purge: a new pure-NURL `redis` client, a compiler
type-checking sweep that converts several silent miscompiles into clear
compile-time errors, and an `O(n²) → O(1)` symbol-table speedup that keeps
whole-program compilation fast now that HTTP pulls in the full TLS+crypto
closure.

**Toolchain requirement:** the minimum supported compiler is now
**clang / LLVM 15+** (was 14+). LLVM 15 emits opaque-pointer IR by default,
so the build no longer needs the `-opaque-pointers` shim for older clangs.

### Added

- **Pure-NURL TLS 1.3 client in the stdlib** (`std/tls.nu`,
  `std/tls_verify.nu`) — promoted from the `tls` package so stdlib HTTP/TLS
  consumers (`anthropic`, `mcp_http`/`mcp_client`, `cluster`, `http_json`,
  `http2_client`) can build on it. The `tls` package is now a thin
  re-export facade for backward compatibility. (§8 P0)
- **Pure-NURL TLS 1.3 server** (`std/tls_server.nu`) — full
  ServerHello / EncryptedExtensions / Certificate /
  CertificateVerify (ECDSA P-256) / Finished handshake over `tcp_accept`,
  EC P-256 private-key PEM loading, ALPN (`h2`) negotiation, and an
  in-place STARTTLS upgrade. `net.nu`'s `TcpConn` is now polymorphic
  (plain / TLS-client / TLS-server) so `http_server` gets clean HTTPS.
  (§8 P4)
- **RSA leaf-certificate support for the pure TLS server** — RSA-PSS
  signing (`rsa_pss_sign_sha256`), PKCS#1/#8 key parsing
  (`rsa_priv_from_pem`), cert-chain transmission, and `tls_accept_rsa`;
  `net.nu` auto-detects EC vs RSA and frames `fullchain.pem`. (PR #289)
- **Pure-NURL crypto** filling the gaps left by the OpenSSL removal:
  AES-256-GCM (`std/aes_gcm.nu`), **Ed25519** sign/verify
  (`std/ed25519.nu`, a TweetNaCl port reusing the x25519 field
  arithmetic), **scrypt** (`std/scrypt.nu`, RFC 7914), PBKDF2-HMAC-SHA512,
  and ECDSA P-256 signing (RFC 6979). All KAT-verified, ASan/LSan-clean.
  (§8 P1/P2/P4)
- **Pure-NURL HTTP/1.1 client** (`ext/http_pure.nu`) over the stdlib TLS —
  one transport+parser driving both the buffered `http_request`/`http_get`
  family and the pull-based `http_stream_*` API: incremental chunked
  decoder (live SSE streaming), Content-Length, redirects (301/302/303/
  307/308), all methods, binary bodies. (§8 P3)
- **Pure-NURL DEFLATE/inflate/gzip/zlib** (`std/deflate.nu`) — RFC 1951
  inflate (puff.c port) + greedy-LZ77 deflate, `crc32`/`adler32`, and
  streaming `inflate_stream` / `deflate_block_dict` for permessage-deflate
  context takeover. `ext/compress.nu` is rewritten over it
  (`zlib_*`/`gzip_*`/`raw_deflate_*`). (§8 P6)
- **`redis` package** — a pure-NURL Redis client speaking RESP2 over a
  libc TCP socket, with optional TLS (`rediss://`) via the pure `tls`
  package, so the binary links `libc` only. Flat-arena RESP2 codec
  (`src/resp.nu`), a typed surface (strings/lists/hashes/sets, `INCR`/
  `EXPIRE`/`TTL`/`KEYS`, full pub/sub), and a `redis-cli`-style CLI with a
  REPL and `SUBSCRIBE`/`PSUBSCRIBE` streaming. Validated live against
  redis:7 (20/20, ASan-clean).

### Changed

- **`ext/crypto.nu` is now a thin facade** over the pure crypto modules —
  the OpenSSL EVP FFI layer (~35 bindings) is gone; the public API and
  `CryptoErr`/`CryptoKeypair` types are unchanged, so `noise`/`session`/
  `jwt`/`http_jwt` consumers compile untouched. (§8 P2)
- **All client-TLS consumers** (`mqtt`, `websocket`, `http2`, `smtp`) now
  route through `net.nu`'s pure `tcp_connect_tls[_alpn]` / `tcp_starttls`
  instead of the OpenSSL-backed runtime helpers. (§8 P4)
- **Compiler: the symbol table is hash-indexed** (FNV-1a buckets) —
  `nurl_sym_get` was a backward linear scan over an append-only table, so
  whole-program compilation was `O(n²)`. Now `O(1)` average lookups with
  identical semantics (byte-identical IR, bootstrap fixed point holds).
  Effect: compiling `examples/http_basic.nu` 11.0s → 0.59s, the examples
  sweep 8m11s → 25s, the corpus stage 7m13s → 1m11s.
- **Minimum toolchain is clang / LLVM 15+** (was 14+). The build scripts
  reject older clangs with install guidance; the `-opaque-pointers` shim
  for clang 13/14 is removed.

### Removed

- **`libcurl`** — the entire C HTTP-client backend (libcurl bridge +
  WinHTTP + stubs, ~850 lines) is deleted from `runtime.c`; `-lcurl` and
  its detection are gone from the build. (§8 P3)
- **`libssl` / `libcrypto`** — all SSL code (the dlopen vtable + ~250
  `SSL_*` call sites, −801 lines) is deleted from `runtime.c`; `-lssl
  -lcrypto` and `NURL_HAVE_OPENSSL` are gone from the build. (§8 P4)
- **`libpq`** — `ext/postgres.nu` (47 FFI bindings) and its examples/test
  are removed; the pure-NURL `psql` package is the replacement. (§8 P5)
- **`libz`** — `nurl_z_*` + the `z_stream` ABI are deleted from
  `runtime.c`; `-lz` and `NURL_HAVE_ZLIB` are gone from the build. (§8 P6)
- Net effect: the default `./build.sh` produces binaries whose `NEEDED` is
  `libc.so.6` only (plus `libm`). `libzstd` and `libsqlite3` remain
  **optional**, behind runtime sentinels and `-Wl,--as-needed`, so a
  program that does not use them still links `libc` only. (§8 P7)

### Fixed

- **Compiler type-check sweep** — a focused pass that turns a class of
  "`nurlc` accepts → `clang` rejects late (or silently miscompiles)" gaps
  into clear compile-time errors. Diagnostic-only: IR for valid programs is
  byte-identical and the bootstrap fixed point holds.
  - **`String` vs `s` (`i8*`) argument mismatch** — passing a raw C-string
    where a `String` parameter is declared (or vice versa) was silent
    wild-pointer UB (it surfaced as a SEGV in `net.nu`'s cert-chain code).
    Now rejected at the call site with a fix-it (`string_data` / `string_from`).
  - **Wrong named struct by value** — passing a `B` where an `A` is
    declared by value type-checked clean and let the callee read the
    foreign struct's leading fields. Now rejected at the call site, in
    return position (`^ b` from a `→ A` fn), and in struct literals (bad
    field type or too many fields).
  - **`^ value` from a `→ v` (void) function** — silently lowered to
    `ret i64 …` out of a `void` LLVM function. Now a clear error, and a
    **bare `^`** is supported as an early return in void functions.
  - **Reassignment and field stores** (`= name v`, `= . obj field v`) — a
    float-into-`i`, wrong-struct, or `String`-vs-`s` store emitted a
    type-mismatched `store` that only clang caught. Now rejected (integer
    width / signedness / pointer-stash coercions stay legal).
  - **`!b` / `?b` bool payloads** in result/option matches were extracted
    as `i64` but used as `i1` (`clang` rejected the IR); a `b` branch now
    truncates the payload back to `i1`.
- **WASM build of the runtime.** `nurl_read_password` (added in 0.9.19)
  included `<termios.h>` on every non-Windows target, which broke the
  `wasm32-wasi` compile (no termios) used by the playground / API image. It
  now uses a WASI fallback branch (echoed read) alongside the POSIX termios
  and Windows console paths; native behaviour is unchanged.

## [0.9.19] — 2026-06-25

A usability pass on the pure-NURL `psql` client: it gains a real psql-style
front end — aligned result tables, a multi-line REPL, and backslash
meta-commands — and now **prompts for a password** when the server requires
one, so it connects to password-protected servers out of the box instead of
failing with an opaque error. The cross-platform hidden password entry is
provided by a new runtime helper, `nurl_read_password`.

### Added

- **Runtime: `nurl_read_password`** — prompt on stderr and read a line from
  the terminal with echo disabled (termios on POSIX, `SetConsoleMode` on
  Windows), restoring the prior console state. The cross-platform home for
  password entry, so packages need not declare platform-specific console
  symbols themselves.

### Changed

- **`psql`: prompt for a password when the server requires one.** Like the
  real `psql`, it now reads the password interactively (echo disabled) when
  the server requests authentication and neither `$PGPASSWORD` nor a URL
  password was supplied — instead of sending an empty password and failing
  with `PgServerError`. Trust-authenticated servers are still connected
  without a prompt.
- **`psql`: a `--help` / `-?` flag.** Bare `psql` again attempts a default
  (localhost) connection like other psql clients; only an explicit `--help`
  prints usage.
- **`psql` package — a proper psql-style front end.** The command now
  renders results as aligned tables (numeric columns right-justified, NULLs
  blank, an `(N rows)` footer), runs a multi-line REPL that accumulates a
  statement until its `;` terminator, shows prompts and a banner only on a
  terminal, and supports backslash meta-commands (`\dt`, `\d TABLE`, `\dn`,
  `\l`, `\du`, `\conninfo`, `\?`, `\q`). It captures the server version and
  the connection identity for the banner and `\conninfo` (which reports
  whether the link is TLS-encrypted). All of this stays pure-NURL — the
  binary still links `libc` only.

### Fixed

- **`psql`: a per-query memory leak.** Each `pg_query` overwrote the
  result's command-tag string without freeing the previous one, leaking one
  allocation per statement over a long session. The REPL is now free of
  per-operation leaks.
- **`psql`: a connection leak on authentication failure.** `pg_connect`
  returned the error without closing the socket or freeing the connection;
  it now closes on the failure path (which the password-retry flow relies
  on).

## [0.9.18] — 2026-06-24

Portability fixes surfaced by real-world installs of the v0.9.17 toolchain:
a program built on a non-x86_64 release could fail to link against OpenSSL,
and the pure-NURL TLS client could not reach TLS-1.2-over-P-256 servers.

### Fixed

- **Every binary now links `libc`-only on every platform — OpenSSL is
  loaded at runtime via `dlopen`.** The shipped `runtime.o` is built with
  OpenSSL, so it referenced `SSL_*` / `X509_*` / `CRYPTO_*`. A program that
  doesn't use runtime TLS only linked `libc`-only if the linker dead-stripped
  those references — which clang/lld LTO does on x86_64 but the bundled-zig
  portable builds do not, so `nurlpkg install` of any `net.nu`-importing
  package (e.g. `tls`) failed on `linux-arm64-glibc` with dozens of
  `undefined symbol: SSL_new / TLS_server_method / …`. OpenSSL is now
  resolved entirely through `dlopen`/`dlsym`, so `runtime.o` carries **zero**
  link-time references to libssl/libcrypto: every program links `libc`-only
  regardless of dead-code elimination, and libssl is loaded lazily the first
  time a TLS connection is created (its absence becomes a clean
  `TLS_CTX_INIT` error rather than a link failure). On Linux the link adds
  `-ldl` (`dlopen` lives in `libdl` below glibc 2.34; `--as-needed` drops it
  where unused); FreeBSD/macOS keep `dlopen` in libc, and Windows is
  unaffected (it uses WinHTTP, not OpenSSL).
- **Pure-NURL TLS reaches TLS-1.2 servers that use P-256 key exchange.** The
  TLS 1.2 fallback only did X25519 ECDHE, so a TLS-1.2 server negotiating
  ECDHE over `prime256v1` (the OpenSSL default `ssl_ecdh_curve`) failed with
  `TlsHandshake`. The 1.2 handshake now reads the `named_curve` from the
  `ServerKeyExchange` and does P-256 ECDHE as well, matching the TLS 1.3
  path. (`tls` package republished as 0.1.1.)

## [0.9.17] — 2026-06-24

A complete **pure-NURL cryptography and TLS stack**, and on top of it a
**TLS client** and a **PostgreSQL client** that need nothing installed on
the target — no OpenSSL, no libpq. Every primitive is implemented from
scratch in NURL and validated against its RFC/NIST known-answer vectors;
the resulting clients link `libc` only. Also ships the `chart`
data-visualisation package and makes the runtime's `libssl` an optional
dependency.

### Added

- **`chart` package** — terminal data-visualisation (sparklines, bar
  charts, histograms, line plots) as both a CLI and a reusable library.
- **Pure-NURL cryptography** in `stdlib/std/`, each validated against its
  RFC/NIST known-answer vectors and ASan-clean:
  - **X25519** key exchange (RFC 7748) — `x25519.nu`.
  - **ChaCha20-Poly1305** AEAD (RFC 8439) — `chacha20poly1305.nu`.
  - **HKDF** + TLS 1.3 key-schedule helpers (RFC 5869 / RFC 8446 §7.1) —
    `hkdf.nu`.
  - **RSA** signature verification — PKCS#1 v1.5 and PSS — plus bigint
    `modpow` / `from_bytes_be` / `to_bytes_be` — `rsa.nu`, `bigint.nu`.
  - **ECDSA** verification on NIST **P-256** and **P-384** — `ecdsa_p256.nu`.
  - **AES-128-GCM** AEAD (NIST SP 800-38D) — `aes_gcm.nu`.
  - **X.509 / DER** certificate parser (TBS, signature algorithm, SPKI,
    validity, SAN, CA flag) with RFC 6125 hostname matching — `x509.nu`.
  - **PBKDF2-HMAC-SHA-256** (RFC 8018) — `pbkdf2.nu`.
  - **P-256 ECDH** (`p256_ecdh_keygen` / `p256_ecdh_shared`) — `ecdsa_p256.nu`.
- **`tls` package — a pure-NURL TLS 1.3 client (RFC 8446) with TLS 1.2
  fallback.** No OpenSSL and no FFI beyond the libc TCP socket. Negotiates
  ChaCha20-Poly1305 and AES-128-GCM over **X25519 and NIST P-256** key
  exchange. **`verify-full` by default**: the CertificateVerify signature,
  the certificate chain up to the system trust store, the validity window
  and the hostname are all checked (`TlsBadCert` otherwise). `tls_attach`
  runs the handshake over an already-connected socket for STARTTLS-style
  upgrades. Ships a `tlsget` HTTPS CLI. Verified live against example.com,
  google.com and cloudflare.com.
- **`psql` package — a pure-NURL PostgreSQL client.** The version-3 wire
  protocol, authentication (trust / cleartext / MD5 / **SCRAM-SHA-256**)
  and an optional **TLS** transport over the pure-NURL stack — **no libpq,
  no OpenSSL**. A secure, authenticated connection works on a host with
  nothing installed; the produced binary's `NEEDED` is `libc` only.
  Installable with `nurlpkg install psql`; usable as a library
  (`pg_connect` / `pg_query`). Verified against a live PostgreSQL 16.

### Changed

- **Importer-relative import resolution.** A `$`-import now resolves
  relative to the importing file first (then the working directory, then
  `$NURL_STDLIB`), so a multi-file package can reference its own modules by
  bare name and build identically standalone, from the monorepo, and as a
  `deps/<name>` dependency. Purely additive — the self-host bootstrap is
  byte-identical.
- **`libssl` is now an optional runtime dependency.** The OpenSSL hot-path
  symbols (`SSL_read` / `SSL_write` / …) are routed through a
  lazily-installed, `volatile` function-pointer vtable, so a program that
  never opens a runtime OpenSSL connection — a pure-NURL-TLS client or a
  plaintext-TCP program — links `libc` only. (`volatile` is required:
  without it, full LTO constant-folds the addresses back into the live
  readers and re-pins `libssl`.) A program that does use runtime TLS
  re-links `libssl` correctly.
- **The compiler dedupes FFI `declare`s by symbol name.** Two imported
  modules may legitimately declare the same libc/runtime extern (e.g.
  `nurl_rand_fill` in both `std/random.nu` and the `tls` package); the
  duplicate IR line is now suppressed instead of failing the build with
  LLVM's "invalid redefinition of function". Generalises the existing
  prelude-symbol skip; purely additive — only fires when a duplicate would
  otherwise error, so the bootstrap is byte-identical.

### Fixed

- **Fiber-scheduler use-after-free on yield.** `nurl_fiber_yield` pushed
  the fiber onto the run queue *before* `swapcontext` returned, so another
  worker could steal, run and free it while the worker loop still read
  `f->state`. The push moved out of `nurl_fiber_yield` into the worker
  loop's runnable branch, after the context is saved. Surfaced
  intermittently by the sanitized test suite (`async_chan`); 0 failures
  under stress after the fix.

## [0.9.16] — 2026-06-23

Makes the Windows toolchain actually usable. v0.9.15 shipped a Windows
archive that installed but couldn't build anything; this release makes it
self-contained and fixes the toolchain bugs that surfaced behind it.

### Fixed

- **Windows toolchain is now self-contained.** The shipped `runtime.o` is
  built with `-DNURL_HAVE_ZLIB`, so it references zlib and EVERY program link
  needs it — but `runtime.winlibs` recorded the CI build machine's absolute
  vcpkg path (`C:\vcpkg\…\zs.lib`), so on a user's box every
  `nurlpkg install`/build died with `lld-link: could not open 'zs.lib'`.
  `build.bat` now copies the resolved static libs into `stdlib\winlib\` and
  records a relocatable fragment that `nurl.bat` resolves against the install
  prefix — the toolchain links against its own bundled zlib/zstd with no
  vcpkg on the box.
- **`nurlpkg install` on Windows.** nurlpkg copied the built binary from
  `pkgdir/.nurl-bin`, but the Windows driver emits `.nurl-bin.exe`, so the
  copy silently failed with `failed to install binary`. Fixed by appending
  `.exe` on Windows.
- **FFI build-time sentinel resolves like a `$`-import.** `__ffi_lib_check`
  looked for `stdlib/runtime.<lib>` relative to the current directory, so a
  program importing `stdlib/ext/compress.nu` failed to compile from any
  directory other than the stdlib tree with a bogus "no build-time sentinel"
  error. It now resolves CWD-first then `$NURL_STDLIB`, matching how
  `$`-imports resolve — so an installed toolchain finds its shipped sentinel
  from anywhere. (Control-flow only; the self-host bootstrap is unaffected.)
- **`nurlc --version` / `nurlpkg --version` on Windows** reported `unknown`:
  `build.bat` never generated `stdlib/nurl_version_gen.h`. Added
  `tools/version.bat` (Windows counterpart of `tools/version.sh`) and wired
  it into `build.bat`, so the real version is baked into `runtime.o`.

### Added

- **Windows PowerShell one-line install** on the website install card
  (`irm https://nurl-lang.org/install.ps1 | iex`), alongside the Linux /
  FreeBSD `curl | sh` command.

## [0.9.15] — 2026-06-23

### Added

- **Prebuilt Windows toolchain.** The release pipeline now publishes
  `nurl-<tag>-windows-x86_64.zip`, built natively on `windows-latest` in CI, so
  the one-line installer works on Windows out of the box
  (`irm https://nurl-lang.org/install.ps1 | iex`). The website install card
  gains a labelled Windows PowerShell one-liner next to the Linux / FreeBSD
  `curl | sh` command. The Windows release job is no longer best-effort — with
  the build fixed below it drops `continue-on-error`, so a future Windows break
  fails the run instead of being silently swallowed.

### Fixed

- **Windows release build (issue #229).** `build.bat` wrote the `-lzlib` link
  fragment whenever `zlib.h` was present, without checking that a matching
  `.lib` actually existed — so `nurlpkg` failed to link with
  `LNK1181: cannot open input file 'zlib.lib'`. The vcpkg zlib static-lib name
  is version-dependent (1.3.1 → `zlib.lib`, but 1.3.2 adopted zlib's new CMake
  and ships `zs.lib`, whose `zlib.pc` is rewritten `-lz` → `-lzs`), which is why
  the build passed on local boxes yet only broke in CI. `build.bat` now probes
  the lib directory for the actual file, derives the `-l<name>` from it, and
  enables zlib only when a linkable lib is present (same name probe for zstd).

## [0.9.14] — 2026-06-23

### Added

- **Prebuilt FreeBSD toolchain.** The release pipeline now publishes
  `nurl-<tag>-freebsd-x86_64.tar.gz`, built on FreeBSD 14 in CI, so the
  one-line installer works on FreeBSD out of the box
  (`curl -fsSL https://nurl-lang.org/install.sh | sh`). The shipped binaries
  depend on `libc.so.7` only; FreeBSD's base clang drives `nurlpkg install`,
  so no compiler is bundled. `get-nurl.sh` detects FreeBSD via `uname -s`.
  Validated end-to-end on real hardware: `nurlpkg install argz-demo &&
  argz-demo --shout hi`.
- **FreeBSD CI.** A FreeBSD VM job builds the compiler, checks the
  self-hosting fixed point, and runs the test corpus on genuine FreeBSD — the
  gate that caught the two FreeBSD bugs fixed below.
- **`nurlc --version` / `nurlpkg --version` / `nurl --version`.** The version
  is derived at build time by `tools/version.sh` (`git describe` → `v0.9.14`
  on a release tag, `v0.9.13-2-gabc-dirty` on a dev checkout; falls back to
  the top `CHANGELOG.md` entry for a git-less source tree) and baked into
  `runtime.o` via a generated, git-ignored header (`stdlib/nurl_version_gen.h`).
  Nothing is hardcoded, and it flows in automatically both in releases and
  local builds. Because the string lives in `runtime.o` and not in
  `nurlc.nu`'s IR, the self-hosting fixed point and the committed bootstrap
  snapshot are unaffected by a version bump.

### Fixed

- **The installed toolchain no longer requires bash.** The shipped wrapper
  scripts (`nurl.sh` and the `nurl` / `nurlc` / `nurlpkg` shims) were
  `#!/usr/bin/env bash`, so on a stock FreeBSD / Alpine / busybox box — where
  the binaries are libc-only but bash is absent — the first build died with
  `env: bash: No such file or directory`. They are now POSIX `sh`, validated
  under dash on Linux and end-to-end on a bash-less FreeBSD 14.3 box.
- **Async fibers run on FreeBSD.** The M:N stackful-fiber runtime was gated to
  glibc/macOS, so on FreeBSD (which has full `ucontext`) it silently fell back
  to a no-op stub and fibers never ran. Now enabled on
  FreeBSD / NetBSD / DragonFly.
- **Empty URL is `HttpInvalidUrl` on a no-libcurl build** (was `HttpOther`),
  matching the libcurl and WinHTTP backends — input validation that no longer
  depends on which HTTP backend is compiled in.
- **`z_stream` ABI helpers decoupled from the zlib build flag**, so a runtime
  linked against libz without `zlib.h` at compile time still reports the
  correct struct size (an ABI replica pinned by `_Static_assert`).
- **Test/example harness portability.** `run_tests.sh` no longer uses GNU
  `sed -i` (mis-parsed by BSD sed); FFI-dependent tests and examples now
  self-skip when their optional library (sqlite3 / libpq / …) is absent
  instead of failing the suite.

### Changed

- **Setup no longer needs `source ~/.nurl/env`.** The shims self-locate the
  stdlib, so `export PATH="$HOME/.nurl/bin:$PATH"` is the whole setup and works
  in any shell. The website one-line install is updated to match and gains a
  Copy button.

## [0.9.13] — 2026-06-23

A one-line follow-up to v0.9.12 that makes the bundled-zig build actually
work on a fresh box.

### Fixed

- **A failed feature-library probe no longer aborts the build.** v0.9.12
  installed and ran on a Raspberry Pi 4 / ODROID, but any build — including
  `nurlpkg install <tool>` — died with a bare `compile failed:`. The
  feature-lib availability probe ended each check with
  `probe && EXTRA_LIBS+=(…)`, so a *failed* probe made the helper return
  non-zero and the build's `set -e` aborted at the first unavailable
  library. A fresh box typically has the runtime `libcurl.so.4` but not the
  `-dev` `libcurl.so` linker symlink, so `-lcurl` (and openssl/sqlite/pq/
  zstd) won't link and every probe failed — killing the build before the
  link step. The probe now uses an explicit `if` and is total, so an
  unavailable library is simply skipped. Verified on a real Raspberry Pi 4
  (glibc 2.31) and ODROID: `nurlpkg install argz-demo && argz-demo --shout
  hi` → `HELLO, HI!`.

## [0.9.12] — 2026-06-23

The "bombproof install" release: the toolchain now installs **and builds**
on old or minimal Linux boxes — a fresh Raspberry Pi / ODROID can run the
`curl … | sh` one-liner and `nurlpkg install <tool>` straight through,
with no system compiler and no surprise library requirements.

### Added

- **Bundled `zig` build backend.** The archive ships a self-contained
  `zig`; `nurl.sh` uses `zig cc` to lower nurlc's LLVM IR to a native
  binary. zig carries its own modern LLVM (so the opaque-pointer IR just
  parses), its own `lld` linker, and libc headers — so **building a program
  (and `nurlpkg install`) needs no system clang at all** and is immune to
  the box's LLVM version. Falls back to a system clang (with
  `-opaque-pointers` on clang 13/14) when no bundled zig is present.

### Fixed

- **The shipped binaries run on old distros.** `nurlc`/`nurlpkg` were built
  on a glibc-2.39 runner and failed to start on e.g. Raspberry Pi OS
  bullseye (glibc 2.31) with `version 'GLIBC_2.34' not found`. They are now
  relinked with the bundled zig against an old glibc floor
  (`tools/relink-toolchain-portable.sh`), landing at **GLIBC_2.25** — which
  covers the Pi and essentially every Linux since ~2017.
- **Feature libraries are linked only when available.** `nurl.sh` probes
  each back-end library (libcurl / OpenSSL / sqlite3 / libpq / zlib / zstd)
  and links it only if it is present on the box; under LTO + `--as-needed`
  an unused one is dropped anyway. A feature-free program — the common
  registry tool — links against **libc only** and never demands a library
  the box lacks (an unconditional `-lpq` previously broke a hello-world
  where the Postgres client was absent).
- **Actionable errors instead of cryptic failures.** A missing compiler
  prints install guidance rather than `clang: command not found`; the
  installer smoke-tests the unpacked binaries and, on a missing shared
  library, names the `.so` with a package-manager hint.

## [0.9.11] — 2026-06-22

The "dependency-free toolchain + registry programs" release: the installed
`nurlc` and `nurlpkg` now link **libc only** (no inherited `libpq` /
`libcurl` / `libsqlite3` / …), several real programs landed on the package
registry, and the whole source tree is now held to canonical `nurlfmt` form
by CI.

### Added

- **WebSocket `permessage-deflate` (RFC 7692), server and client.** Per-message
  compression negotiated over `Sec-WebSocket-Extensions`, with both context-
  takeover directions and peer-imposed window bounds honoured. New surface in
  `stdlib/ext/websocket.nu`: extension negotiation (`ws_deflate_parse_extensions`,
  `ws_deflate_offer_header`, `ws_deflate_response_header`), a `WsDeflate` context
  (`ws_deflate_make` / `ws_deflate_free`), deflate-aware messaging
  (`ws_send_text_deflate` / `ws_send_binary_deflate` / `ws_read_message_deflate`
  / `ws_serve_messages_deflate` and their `ws_client_*` mirrors), and one-shot
  handshake helpers (`ws_perform_handshake_deflate`, `ws_connect_deflate`). The
  frame reader now surfaces the RSV1 compressed bit (`WsFrame.rsv1`,
  `WsMessage.compressed`) — still rejected on the non-deflate readers, so the
  change is fully backward-compatible. Decompression is capped against
  `WsLimits.max_message_bytes` (a decompression-bomb guard) and text payloads
  are UTF-8-validated *after* inflation.
- **Raw-DEFLATE streaming codec in `stdlib/ext/compress.nu`** (the engine the
  above rides on): `raw_deflate_*` / `raw_inflate_*` drive a *persistent*
  `z_stream` with raw (header-less) DEFLATE via negative `windowBits`,
  `Z_SYNC_FLUSH`, sliding-window context takeover, and `*_reset`. Four new
  layout-absorbing `nurl_z_*` accessors in `runtime.c` let the NURL-side loop
  rebind input/output across the persistent stream. Regression tests
  `compress_rawdeflate.nu` and `ws_permessage_deflate.nu`.
- **Real programs on the package registry.** Three CLI/library packages were
  written in NURL and published to `reg.nurl-lang.org`: **`nq`** (a jq-lite
  JSON query tool), **`md2html`** (a Markdown → HTML converter, CLI + library),
  and **`iforest`** (Isolation Forest anomaly detection, CLI + library).
  `argz` / `argz-demo` gained READMEs and published `0.1.1`.
- **Registry renders each package's README.** A package's detail page now
  renders the README from its tarball (Markdown → HTML done in TypeScript,
  XSS-safe).
- **`nurlweb` auto-generates release-coupled facts and serves the installer.**
  Site facts (version, line/test/module counts) are generated from the repo
  state instead of being hand-maintained, and `nurl-lang.org` serves the
  installer scripts so the `curl … | sh` one-liner works.

### Fixed

- **Bombproof toolchain install — `nurlc` and `nurlpkg` link libc only.** A
  fresh install could die immediately with
  `error while loading shared libraries: libpq.so.5`, even though `nurlpkg`
  never touches Postgres: the monolithic `runtime.o` carries every FFI
  back-end, and the link lines named them all unconditionally with no
  `--as-needed`, so each binary inherited whatever the build machine had as a
  hard `DT_NEEDED`. Every native link line now passes `-Wl,--as-needed`
  (a binary keeps a dependency only for a library it actually references;
  LTO drops the dead back-end code first), and `nurlpkg` reaches the registry
  through the system `curl` **binary** (new `stdlib/ext/http_cli.nu`) with
  zlib + zstd linked statically — so both `nurlc` and `nurlpkg` now depend on
  `libc` only. The installer (`get-nurl.sh`) also smoke-tests the unpacked
  binaries and reports any missing shared library with a package-manager hint.
- **Windows build.** Build breakage on the Windows target was fixed.
- **`nurlc`: `Vec[T]` indexing when `T` has a field named like the index
  variable.** A struct-pointer field access could be mis-resolved as an array
  index (and vice-versa) when a local index variable shared a name with a
  struct field; the field/element disambiguation is now correct.
- **Playground self-heals a wedged container Worker.** When the backing
  server hangs-but-keeps-running, the Cloudflare container Worker now detects
  the "not listening" wedge and restarts it instead of serving sticky 500s.

### Changed

- **Canonical-form gate.** The whole tree was canonicalised with `nurlfmt`
  and a `nurlfmt --check` CI gate now rejects any non-canonical first-party
  `.nu` file (the formatter is IR-transparent, so this changed no behaviour).

### Docs

- Roadmap: the two LLM-native evidence studies are marked as shipped.

## [0.9.10] — 2026-06-20

The "NURL becomes an ecosystem" release: the toolchain is now installable,
the package registry can host and install real programs, and tagged
releases ship install packages for Linux and Windows.

### Added

- **`$NURL_STDLIB` import root (the compiler is relocatable).** `nurlc`
  resolved every `$ `…`` import path relative to the current working
  directory with no notion of an installed stdlib, so a package could not
  reference `stdlib/…` outside the monorepo. `__norm_import_path` now falls
  back to `$NURL_STDLIB/<path>` (via libc `getenv`) when a cwd-relative hit
  misses; the cwd hit always wins, keeping the bootstrap byte-identical.
  This is what lets an installed compiler — and registry-installed packages
  — find the shipped stdlib from any directory.

- **`nurlpkg install <name>` — install a program from the registry.** The
  `cargo install`-shaped sibling of bare `install`: fetch a published
  package, resolve its dependencies, compile its `src/main.nu` against the
  installed stdlib, and drop the binary in `$NURL_HOME/bin` (default
  `~/.nurl/bin`). A package with `src/main.nu` is an installable program
  (binary = package name); without it, a library. Shell-free and
  cross-platform: staging via the language's own filesystem primitives
  under the platform temp dir, in-process dependency resolution, and a
  build-driver spawn that wraps `.bat` with `cmd /c` on Windows.

- **Installable toolchain — `tools/install-toolchain.sh` / `.bat`.** Install
  `nurlc`, `nurlpkg`, and the stdlib into a self-contained prefix (default
  `~/.nurl`) and wire up `NURL_STDLIB` + `PATH` so the whole toolchain works
  from any directory. The shims and `env` are relocatable (they resolve the
  prefix from their own location), so a downloaded archive works wherever it
  is unpacked.

- **Release pipeline — `.github/workflows/release.yml`.** On a `v*` tag,
  build the toolchain natively for `linux-x86_64-glibc` (ubuntu-latest),
  `linux-arm64-glibc` (ubuntu-24.04-arm), and `windows-x86_64`
  (windows-latest), package each as a relocatable archive + `.sha256`, and
  attach them to the GitHub Release. `workflow_dispatch` gives a
  publish-free dry run.

- **One-line installer — `tools/get-nurl.sh` / `get-nurl.ps1`.** The
  `curl -fsSL https://nurl-lang.org/install.sh | sh` front door: detect
  OS/arch, resolve the latest (or pinned) release, download the matching
  archive, verify its SHA-256, and unpack the toolchain into `$NURL_HOME`.
  `$NURL_INSTALL_BASE` overrides the download base for internal mirrors.

- **First registry packages — `packages/argz` + `packages/argz-demo`.**
  `argz` is a tiny, dependency-free command-line argument parser (boolean
  flags, value options, short aliases, `--` separator, positional arguments,
  auto-generated `--help`), leak-clean under AddressSanitizer/LeakSanitizer.
  `argz-demo` is an installable greeter that depends on `argz = "^0.1"`.
  Both are published to `reg.nurl-lang.org`.
  `tools/nurlpkg/test-install-tool.sh` drives the full fetch → build →
  install → run loop against a local static registry.

### Fixed

- **The language server no longer crashes on an unresolvable import.** The
  LSP's workspace indexer read imported files with the compiler's
  `nurl_read_file`, which calls `exit(1)` on a missing file (a missing
  import is fatal to a *compile*, but must never be fatal to the *server*).
  Opening a file whose imports don't resolve — e.g. a package whose registry
  dependencies aren't installed yet — killed the whole language server. It
  now probes with `file_exists` first (`__read_if_exists`).

- **Duplicate `getenv` declaration removed from `env.nu`.** Now that the
  compiler globally declares `getenv` (for import-path resolution), `env.nu`
  re-declaring it via the `&` FFI form emitted two `declare @getenv` lines
  and failed to link; `env.nu` relies on the compiler-provided declaration,
  matching how `fopen`/`access` are handled.

### Documentation

- **`RELEASING.md`** — the distribution model (GitHub Releases + a `curl|sh`
  front door served from nurl-lang.org; the registry stays the *package*
  registry), how to cut a release, runtime dependencies, and the
  Windows/macOS caveats.

- **`packages/README.md`** — the two registry packages and the full
  install-and-run loop on POSIX and Windows.

## [0.9.9] — 2026-06-18

### Fixed

- **Signedness-aware generic monomorphisation (distinct instantiations for `i` and `u64`).** Generic code using signedness-sensitive operations (like `/`, `%`, `>>`, or comparison operators) now monomorphises correctly based on the concrete type argument's signedness. Previously, types with the same LLVM width (e.g. `i` and `u64`) shared the same mangled slug, causing the compiler to reuse the first generated monomorphisation (e.g., executing `udiv` instead of `sdiv`). Mangles generic type arguments from their source word (`u8`/`u16`/`u32`/`u64` vs `i64`) to force distinct instantiations.
  Regression: `compiler/tests/generic_signedness_mono.nu`.

- **Correct zero-extension for unsigned-returning generic calls.** Widening casts (`# i ( f … )`) of generic call results now zero-extend (instead of sign-extend) the result when the function's declared return type is unsigned. The return signedness of the monomorphised instantiation is now tracked and resolved at the call site.
  Regression: `compiler/tests/unsigned_call_result_widen.nu`.

- **Integer literals above `i64` max parsed correctly in `u64` range.** The decimal lexer now accumulates digits using wrapping 64-bit arithmetic instead of `atoll` (which silently saturated at `LLONG_MAX` for literals in `[2^63, 2^64)`).
  Regression: `compiler/tests/u64_literal_parsing.nu`.

- **Foreach elements inherit container's unsigned element type.** Element variables in `~ x container { … }` loops now correctly inherit the container's unsigned type (recovered from the vector/slice metadata), ensuring signedness-sensitive operations and widening casts inside the loop execute with unsigned semantics.
  Regression: `compiler/tests/foreach_unsigned_element.nu`.

- **IEEE 754 NaN semantics for float inequality (`!=`).** Float `!=` comparisons now emit `fcmp une` (unordered-or-not-equal) instead of `fcmp one` (ordered, not-equal), correctly returning `true` when either or both operands are NaN.
  Regression: `compiler/tests/float_ne_nan.nu`.

- **Result Ok-arm payload inherits type's unsigned flag.** Pattern matching over a Result `! T E` now correctly propagates T's unsigned flag to the Ok-arm (`T v`) binding inside the match block, correcting signedness-sensitive operations on the payload.
  Regression: `compiler/tests/result_payload_unsigned.nu`.

- **Result Err-arm payload inherits type's unsigned flag.** Dual to the Ok-arm fix, the Err-arm (`F e`) binding now correctly inherits E's unsigned flag from a Result `! T E` type.
  Regression: `compiler/tests/result_err_arm_unsigned.nu`.

- **Monomorphised generic struct fields retain unsigned signedness.** Field type substitutions in `ensure_struct_instantiated` now propagate the unsigned flag, preventing unsigned fields of generic struct instances from being treated as signed on field access (e.g. `. p field`).
  Regression: `compiler/tests/generic_struct_field_unsigned.nu`.

- **Coercion of float literals to `f32` struct fields.** Float literals (always parsed as `double`) are now correctly truncated to `float` (via `fptrunc`) when initializing `f32` fields of structs/aggregates, resolving "insertvalue operand and field disagree in type" compilation errors.
  Regression: `compiler/tests/f32_struct_field_literal.nu`.

- **Enum `f32` payload construction support.** Float payloads constructed for `f32` enum variants now correctly perform float narrowing (`fptrunc`) from double literals or values before insertion, allowing float-payload enums to round-trip.
  Regression: `compiler/tests/enum_f32_payload.nu`.

- **Two more fuzzer BAD_IR shapes diagnosed (bool/int mix, match on a scalar).**
  - **A binary operator mixing a bool (i1) and a non-bool operand**, both
    non-constant (`< flag n` with `n : i`), emitted a width-mismatched
    `icmp i1 %flag, %n` that only clang/llvm-as rejected. `gen_binary` now
    rejects it. A constant operand is still fine — it reinterprets to the other
    side's width — so `== flag 0` (int literal fits i1) and `== v T` (bool
    literal fits i64) keep compiling; only two disagreeing registers are
    flagged.
  - **Binding a payload while matching a non-aggregate scalar** (`?? n { T a →
    … }` with `n : i`) emitted an `extractvalue` on the scalar. `gen_match` now
    rejects payload binding unless the scrutinee is an enum / option / result;
    integer-literal arms and bare tag matches are unaffected.
  Locks `should_fail_binop_bool_int`, `should_fail_match_payload_scalar`. (One
  deeply-contrived fuzz holdout remains: a mutation that makes a match
  scrutinee's *declared* type claim an option/result while its actual SSA value
  is a scalar — an inconsistency no real program produces.)

- **Option / Result `??` arm payload arity is enforced (fuzz follow-up #3).** An
  Option (`? T`) or Result (`! T E`) match arm binds at most one payload — the
  T-arm value / Ok payload, or the F-arm error. Binding more (`?? o { T a b → …
  }`) used to emit an out-of-range `extractvalue { i1, T } v, 2` that nurlc
  accepted (rc 0) and only clang/llvm-as rejected. `gen_match` now reports
  *"match arm binds N payloads but an option/result 'T' arm binds at most
  one …"*. (Enum variants already validated per-variant payload arity; this
  closes the opt/res case, completing the in-`??` out-of-range-extractvalue
  class.) Locks `should_fail_match_opt_overbind`.

- **More front-end checks for type/field misuse (fuzz follow-up #2).** The
  mutation fuzzer's remaining `BAD_IR` shapes (nurlc rc 0, only clang/llvm-as
  rejecting) were turned into source diagnostics — and one of the new checks
  caught a genuine latent bug in the corpus:
  - **A function / FFI symbol name used where a type is expected** now reports
    *"unknown type 'X'"*. The earlier unknown-type check accepted any name in
    scope; it now requires a `%`-type, so `@ f rand x → i` (using the FFI symbol
    `rand` as a parameter type) is rejected too.
  - **`.` field/element access on a non-aggregate scalar** (`. n x` with `n : i`)
    is rejected — it used to emit `extractvalue i64 …`.
  - **An out-of-range integer index into an aggregate** (`. p 9` on a 2-field
    struct) is rejected — it used to emit an invalid `extractvalue …, 9`.
  - **Accessing a field a struct does not have** (`. p nope`) now reports
    *"type 'P' has no field 'nope'"* instead of silently reading field 0 (a
    miscompile) — this exposed and fixed a real `. pho req` typo in
    `compiler/tests/websocket_client.nu` that had been reading the right field
    (`head`, index 0) only by luck.
  - **An FFI declaration whose `@` is not followed by an identifier**
    (`& "lib" @ @ foo`) is rejected with *"expected the C function name …"*.
  Locks `should_fail_{type_is_fn_name, member_on_scalar, member_index_oob,
  unknown_field, ffi_no_name}`. (Remaining, deferred: a `??` arm that binds more
  payloads than its variant/option has still emits an out-of-range
  `extractvalue` — a `gen_match` concern for a future round.)

- **Unknown type names are diagnosed at the source (fuzz follow-up).** An
  undeclared type identifier in a type position — an FFI parameter/return type,
  a function parameter/return type, or a struct field type — used to leak into
  the IR as an undefined `%Name` that `nurlc` emitted with status 0 and only
  `clang` / `llvm-as` rejected ("use of undefined type named 'X'", or the
  cryptic "cannot allocate unsized type"). A typo'd type name or a missing `$`
  import now produces *"unknown type 'X' … (a typo, or a missing '$' import?)"*
  pointing at the use. The new `check_type_known` scans the emitted LLVM type
  for `%Name` references and verifies each against the pre-scan type registry;
  generic type variables (tparam-like, substituted at monomorphisation) and
  compiler-mangled names (containing `__`, e.g. a `%Vec__i64` instantiation or
  an aliased import) are accepted unchanged, so generics and imports are
  unaffected. Locks `should_fail_unknown_type_{ffi,param,return,field}`.

- **Compiler no longer hangs on an unterminated declaration body (fuzz sweep).**
  A corpus-seeded mutation fuzzer (36k + 15k mutants over `build/nurlc`; oracle:
  never crash, never hang, and rc 0 ⇒ the IR assembles) found **zero crashes**
  but a class of infinite loops: several body-parsing loops checked only for
  their closing token (`}` / `)` / `]`) and not for end-of-input, so an
  unterminated construct spun forever on a no-op `nurl_lex_advance` at EOF
  instead of erroring. A playground user mid-keystroke (or any truncated file)
  could wedge the compiler. Fixed by adding an EOF guard to every such loop and
  letting the trailing `expect` report a clean "expected '}' / ')' / ']' but
  found end of input":
  - enum-variant loop (`: | E { A`),
  - trait/impl scan + gen loops and the method-signature skip
    (`% Shape { @ area i s → i`, `% Shape i { …`),
  - the `[T]` type-param skip, and
  - `parse_type_paren`'s generic-application and closure-type argument loops
    (`( Vec i`, reachable in any type position).
  Struct / match / block / call-argument bodies already terminated (their inner
  sub-parsers hit EOF first) and were left unchanged. 15k post-fix mutants
  produce no hangs and no crashes. Locks `should_fail_unterminated_enum`,
  `_trait`, `_impl`, `_type_paren`.

- **Front-end type checking for the common static-error class (adversarial
  sweep #3).** A sharper probing pass found that a whole family of trivial type
  errors was accepted by `nurlc` (rc 0, no diagnostic) and emitted IR that only
  `clang` rejected — the "where is the type checker?" optics. All are now caught
  at the source, with no implicit conversions introduced (NURL stays explicit):
  - **Binary-operator operand mismatch** — mixing a float and a non-float in any
    operator (`+ 1 1.0`, `* 2.0 3`, `== 1 1.0`), or a pointer/string and an
    integer in an arithmetic op (`+ `a` 1`). `gen_binary` enforces the
    "operands share a type" invariant it already documented. Pointer
    comparisons (`== ptr 0`, ptr↔ptr) stay exempt via the existing ptrtoint
    coercion. Locks `should_fail_binop_int_float`, `should_fail_binop_ptr_int`.
  - **Binding initialiser / assignment mismatch** — `: i x 1.5`, `: i x `hi``,
    `= n 1.5`. `coerce_store_val` now rejects the never-valid float/non-float
    and pointer-into-non-pointer store clashes after its real coercions
    (i1-widen, enum-wrap, single-handle, int-width) have had their say; the
    null-as-`0` idiom (`: *T p 0`) stays valid. Locks
    `should_fail_let_type_mismatch`, `should_fail_assign_type_mismatch`.
  - **Return-value type mismatch** — `^ `hi`` / `^ 1.5` from a `→ i` function.
    `gen_ret` checks the returned value's type against the declared return type
    (same narrow never-valid directions). Locks
    `should_fail_return_type_mismatch`.
  - **Void/unit value (`v`) stored or bound** — `: i y v`, `= x v` (the bare
    type keyword leaking into a value position). Locks `should_fail_store_void`;
    the operator/complement/not sinks were already guarded.
  - **Recursive struct of infinite size** — `: Node { i v  Node next }` (a
    by-value self-reference, the classic missing-pointer mistake) is diagnosed
    at the declaration with the "box it as `* Node`" cure, instead of a cryptic
    `insertvalue operand and field disagree` IR error at first construction.
    Locks `should_fail_recursive_struct`.
  - **Closure return-type context** — `gen_ret` inside a closure body now sees
    the *closure's* declared return type (the body scope shadows
    `__fn_ret_ty__`), not the enclosing function's; this both enables the
    return check above inside closures and corrects the pre-existing
    void-return diagnostic there.

### Decided (toward 1.0 grammar lock)

- **No grouping/closing delimiter — locked.** Fixed prefix arity with no
  closing token stays the canonical, permanent surface form (CRITIC A3, the
  last open grammar decision). The call was made on data: a ~77 000-line
  first-party corpus sweep (the self-hosted compiler, the HTTP/1.1+2 +
  WebSocket stack, a regex engine, crypto, and the Game Boy / C64 emulators)
  measured the longest consecutive prefix-operator run per line — ~96 % of
  operator-bearing lines nest only 1–2 deep, and just **19 lines in the entire
  corpus** reach depth ≥5, clustered in two idioms (n-ary boolean membership
  and big-endian byte assembly) that already have ordinary library answers (a
  predicate helper such as `is_alpha`, or an intermediate `:` binding). The
  foot-gun shape is caught by the existing dead-value / prefix-arity-cascade
  diagnostics. Rationale and the depth table are recorded in `docs/spec.md`
  §6. The decision is safe to revisit additively — an *optional* grouping form
  could be added post-1.0 without breaking any program; 1.0 locks only the
  negative.

### Changed

- **Clearer diagnostics for two call-site papercuts** (surfaced by the
  v1.0-lock language sweep):
  - A **generic function called without `[T …]` type arguments** now reports
    *"generic function 'pick' needs explicit type argument(s): write
    ( pick [T] … ) — NURL does not infer generic type arguments from value
    arguments"* instead of the misleading *"call to unknown function 'pick'"*
    (the same message a genuine typo gets). A truly-unknown name still gets the
    unknown-function message. Lock `compiler/tests/should_fail_generic_no_typeargs.nu`.
  - A **pure-NURL stdlib helper used without importing its module** —
    `nurl_str_cat` / `_cat3` / `_cat4` / `_slice`, which are pre-registered for
    cross-module typing but have no C body (unlike `nurl_str_int` / `_float` /
    `read_*`) — now reports *"'nurl_str_cat' is defined in
    stdlib/core/string.nu … add a '$' import of that file"* at the call site,
    instead of leaking clang's *"use of undefined value '@nurl_str_cat'"* at
    link. Safe because `scan_fn_sigs` is a complete whole-program pre-pass, so a
    real definition anywhere sets `__arity` before any call is generated (no
    false positive for cross-module callers). Lock
    `compiler/tests/should_fail_stdlib_helper_no_import.nu`. Both are
    diagnostic-only — the bootstrap fixed point holds.

### Fixed

- **Adversarial language-probing sweep #2 (`examples/chaotic-aggressor.nu`) —
  four edges hardened before the v1.0 lock.** A hostile valid-NURL stress demo
  (a concatenative stack VM exercising generics, traits, multi-payload `??`,
  a slice-of-closures jump table, closures-returning-closures and dense prefix
  float math) flushed out:
  - **Slice element access by a parameter index emitted malformed IR.**
    `. slice idx` where `idx` was a bare function parameter lowered the index
    as a load from a `<name>__ptr` alloca a parameter never has, leaving the
    `load i64, i64*` pointer operand blank — IR nurlc accepted (rc 0) and only
    clang rejected (*"expected instruction opcode"*). `gen_member` now resolves
    the index exactly like `gen_ident` (parameter → `%name`, local → load
    `__ptr`, const / enum → load `@name`). Regression
    `compiler/tests/slice_index_by_param.nu`.
  - **A bare type keyword used as a value emitted `add void void, …`.** The
    void/unit literal `v` (produced only by a bare type keyword in value
    position) reaching an operator / complement / logical-not lowered to a
    void-typed SSA operand — again rc 0, clang-only rejection. New
    `die_if_void` guard rejects it at the source (covers `: i x + v 100` and
    the `~ v xs { … }` foreach-binding trap). Lock
    `compiler/tests/should_fail_void_operand.nu`.
  - **Closure capture-by-value assignment is no longer silent.** Assigning to a
    binding a closure captured by value (the counter footgun: `1,1,1` instead
    of `1,2,3`) now warns at the assignment, pointing at the supported
    shared-mutation shape (a `: ~` multi-field struct captured by reference,
    which cannot escape its frame). Baseline
    `compiler/tests/should_warn_byval_capture_assign.nu`.

### Changed

- **`generic_inst` grammar widened to match the implementation (compound type
  arguments).** The compiler has always accepted compound generic arguments —
  a nested application `( Pair ( Box i ) i )`, a pointer `*T`, an option
  `?T` / `??T`, or a closure `( @ R P* )` — at both the type-position
  `( Name … )` form and the call-site `[ … ]` form, but `spec/grammar.ebnf`
  still said *"base identifiers only; `*T` is not accepted."* The grammar and
  `docs/spec.md` now define a shared `generic_arg` covering those forms, so
  spec and implementation agree ahead of the 1.0 lock. The one excluded shape —
  a bare anonymous slice (`[ T`) as an argument — used to emit garbage IR that
  only clang rejected and now gets a clean source diagnostic with the
  wrap-in-a-struct cure. Lock `compiler/tests/should_fail_slice_generic_arg.nu`.

- **Mutable string globals (`: ~ s g …`) can now be reassigned.** The
  declaration was accepted and emitted as writable `global i8*` storage, but
  `gen_const_decl`'s string branch never recorded the `__mutable` flag (the
  `i` / `u` / `f` / `b` branches all did), so a later `= g …` was wrongly
  rejected with *"cannot assign to immutable global"* — even though the
  grammar lists `s` as an updatable mutable-global type. The string branch now
  sets the flag like the other scalar branches. Reassignment to a constant or
  a heap-allocated (`nurl_str_cat`) string both work. The bootstrap fixed
  point holds (no in-tree code could use a mutable string global, since the
  bug rejected them, so emitted IR is unchanged). Regression
  `compiler/tests/mutable_string_global.nu`. Surfaced by an adversarial
  language-probing sweep for grammar/spec-vs-compiler gaps before the v1.0
  lock.

### Changed

- **Pattern matching now binds N payloads per arm (was capped at 3).** The
  enum type and construction already supported any number of payload slots;
  only the match side was limited — the parser stored just three binding
  names and the emitter had three hand-unrolled slot blocks, so a 4th+ payload
  was silently dropped (`use of undefined identifier`), forcing a post-match
  `.` extraction. The parser now collects overflow payload names/literals and
  the emitter binds slots 1..N-1 through one `emit_enum_payload_bind` helper in
  a loop (slot 0 keeps its option/result-aware reconstruction); literal
  constraints on slots 3+ loop the same way. Verified for 4- and 5-payload
  variants across mixed payload types (int / float / string / pointer /
  struct), a literal constraint on slot 3, and a guard reading a slot-3
  binding. The bootstrap fixed point holds without a refresh. Regression
  `compiler/tests/match_payload_n.nu`. Removes the `docs/LIMITATIONS.md` Enums
  limitation (CRITIC A6).

### Fixed

- **Float (`f` / `f32`) enum payloads now compile.** An enum's payload slot
  is uniformly pointer-typed; construction coerced `i1` / integer / string /
  struct payloads into it, but had no branch for `double` / `float`, so a
  float payload emitted `insertvalue %E …, double X, 1` into a `ptr` field
  and clang rejected it (`operand and field disagree in type`). The match
  side had the symmetric gap. Any sum type with a floating-point payload —
  a numeric AST, a real-valued JSON, a geometry variant — was uncompilable,
  although the grammar permits it. Fixed in `gen_agg_lit` (bitcast the float
  to a same-width int, f32 widens i32→i64, then `inttoptr` into the slot) and
  `emit_enum_float_extract` (the inverse on the match arm). Verified across
  payload slots 0/1/2, a mixed float+pointer recursive enum, and a genuine
  `f32` value; the bootstrap fixed point holds (no existing code used float
  enum payloads, so emitted IR is unchanged). Regression
  `compiler/tests/enum_float_payload.nu`; surfaced by the
  `examples/chaotic-showcase.nu` grammar stress test (recursive symbolic
  autodiff). An *implicit* double-literal → `f32` narrowing in an enum
  literal still needs an explicit `# f32` cast, exactly as struct
  construction requires.

## [0.9.8] — 2026-06-15

### Added

- **NAT- and mobile-traversing distributed transport (§7.4).** A complete
  pubkey-addressed overlay where a peer is a **public key, not an address** —
  it reaches that key over a direct peer-to-peer path when it can and a relay
  when it must, and never drops to zero reachability. Built bottom-up:
  `net/securedgram.nu` (WireGuard-style encrypted UDP over Noise + a session
  AEAD with a sliding replay window, plus endpoint **roaming** so a peer survives
  a network change), `net/stun.nu` (RFC 8489 server-reflexive discovery),
  `net/nat.nu` (candidate gathering, NAT-type classification, UDP hole punch),
  `net/relay.nu` (DERP-style opaque forwarding **plus group multicast** —
  broadcast to your own group), `net/rendezvous.nu` (signaling-only directory),
  `net/transport.nu` (the flat seam: `transport_send`/`broadcast`/`recv`,
  direct-when-possible/relay-when-forced with promote/demote), and SWIM
  membership (`net/membership.nu`) hardened by **Lifeguard**
  (`std/lifeguard.nu`) with a failure-detector control loop
  (`net/failuredetector.nu`). On top sit the sharding + replicated-state
  layers: a consistent-hash ring (`dist/ring.nu`), state-based CRDTs
  (`dist/crdt.nu` — PN-Counter, LWW-Register, OR-Set) and their gossip wiring
  (`dist/replicator.nu`, anti-entropy scoped to a key's replica set). Documented
  end to end in [`docs/DISTRIBUTED.md`](docs/DISTRIBUTED.md).

- **The Crown — distributed computation (§7.5).** Turns the distributed *state*
  above into distributed *work*. `dist/identity.nu` gives each peer a replica
  id; `dist/job.nu` is the keystone — submit a task keyed by `k`, the ring owner
  executes it via a registered handler, the result is recorded idempotently, and
  a key that re-homes mid-flight is **forwarded** to the new owner so the job
  still completes. `dist/lease.nu` adds fencing tokens (epoch monotonicity +
  idempotency keys) so a *side-effecting* task fires **at most once** across a
  split-ownership window. Liveness under load is handled by SWIM
  **self-refutation** plus a **heartbeat on a dedicated OS thread**
  (`dist/heartbeat.nu`), so a 100%-CPU node is not falsely evicted. The whole
  story is verified by a **deterministic chaos-simulation harness**
  (`dist/sim.nu`): a virtual clock + in-process message bus with seeded fault
  injection (drop, latency/jitter→reorder, partition/heal) drives the *real*
  stdlib logic, with scenarios for converge-under-loss, keystone-across-
  partition, at-most-once-side-effect, and CPU-pinned-not-evicted — all
  byte-reproducible goldens, ASan-clean.

- **Push-To-Talk voice app — `pttvoice/`.** A distributed PTT voice app on the
  overlay: captures the microphone, **Opus**-encodes it (48 kHz mono, 20 ms
  frames via a libopus FFI binding), and pushes a talkspurt either to one peer
  (unicast — p2p when punchable, relayed otherwise) or to the whole group
  (multicast); a receiver decodes and plays it. ALSA capture/playback
  (`audio.nu`), the codec (`opus.nu`), the voice wire frame (`proto.nu`), and
  the app (`ptt.nu`) live in a self-contained folder. Verified live over a
  loopback relay (group broadcast and peer unicast). `build.sh` now detects
  **libopus** and **ALSA** (dropping `stdlib/runtime.{opus,asound}` sentinels)
  and `nurl.sh` auto-links `-lopus`/`-lasound` when those FFI symbols appear.

- **Playground “🎙️ PTT Chat” demo with channels.** A new `/pptchat` tab: a
  page with a microphone button and an **embedded NURL→WebAssembly module**
  (`nurlapi/static/pptchat.nu` → `pptchat.wasm`) that reads the mic through the
  `audio` FFI and paints a live VU meter + frequency spectrum, framing the
  distributed voice tech. **Channels**: no id → the shared `public` channel;
  **+ Create channel** mints a random id and navigates to `/pptchat/<id>`;
  opening that URL joins the same channel (the URL is the invite, the future
  shared-secret/QR), with a Copy-link button.

- **Parallel sanitizer test suite.** `compiler/tests/run_san_tests.sh` now runs
  AddressSanitizer/UBSan checks in parallel (`NURL_SAN_JOBS`, default = cores),
  cutting the sanitized CI leg from minutes to under one — matching the already-
  parallel functional runner.

- **HTTP client cookie jar — `stdlib/ext/cookies.nu`** (critic B23). The
  server side writes `Set-Cookie` (ext/http_auth.nu); this is the missing
  client half. `cookie_jar_set` parses one `Set-Cookie` value (Domain,
  Path, Expires, Max-Age, Secure — Max-Age wins over Expires, an
  already-expired cookie deletes its stored match) defaulting Domain/Path
  from the request host/path; `cookie_jar_header` returns the `Cookie:`
  value for a request, applying RFC 6265 domain matching (§5.1.3,
  host-only vs subdomain), path matching (§5.1.4), Secure gating, and
  expiry, longest-path-first. Pure string-in/string-out — decoupled from
  the HTTP client types, so it round-trips a session over HTTP/1.1, h2,
  or any header source. `now` (unix seconds) is passed explicitly for
  deterministic expiry. Lock: `compiler/tests/cookies_basic.nu`
  (host-only vs Domain, path ordering, Secure, Max-Age/Expires expiry,
  replacement, Max-Age=0 deletion, malformed rejection); ASan+UBSan+LSan
  clean.

- **Benchmark harness — `stdlib/std/bench.nu` + `nurlpkg bench`** (critic
  C4). `std/bench.nu` times a no-arg closure over many iterations and
  reports **ns/op** (via the monotonic clock) and **allocations/op**.
  `bench_run name iters body` runs a short untimed warmup then a timed
  loop; `bench_auto name body` auto-scales the iteration count until a
  pass clears ~50 ms, for stable numbers on sub-microsecond operations.
  `bench_report` prints one line; `bench_result_*` accessors expose the
  raw numbers. The allocation metric is backed by a new runtime hook,
  `nurl_alloc_count` (a relaxed-atomic counter on every
  `nurl_alloc`/`nurl_zalloc` — which is what stdlib vec/string/struct
  blocks route through), snapshotted around the timed loop so warmup is
  excluded. `nurlpkg bench` discovers `benches/*.nu`, compiles each at
  `-O2`, runs it, and streams its report (no goldens — wall time is
  machine-dependent; a bench fails only on a compile error or nonzero
  exit). Ships `bench/stdlib_hotpath.nu` (string build / vec push / sort
  micro-benches). Locks: `compiler/tests/bench_basic.nu` (deterministic
  surface — report formatting, the alloc counter on a vec cycle vs a
  no-op body, iteration bookkeeping) and
  `compiler/tests/nurlpkg_bench_smoke.sh` (runner discovery / streaming /
  summary / exit codes).

- **`nurlpkg test` — user-facing test runner** (critic C3). Ships the
  compiler suite's per-test pattern as a tool: `nurlpkg test` discovers
  `tests/*.nu`, compiles and runs each, and reports `PASS`/`FAIL` with a
  summary (exit 0 iff every test passes). A test passes on exit 0; if a
  `tests/outputs/<name>.txt` golden exists, the program's stdout must
  match it byte-for-byte instead. Tests run in sorted order for
  determinism. The build driver is `./nurl.sh` by default, overridable
  via `$NURL_CC` (a command taking `<flags> <src> <outbin>`) for an
  installed toolchain. Smoke-tested by
  `compiler/tests/nurlpkg_test_smoke.sh` (all four verdict paths +
  all-pass/any-fail exit codes + the empty-tree message).

- **REPL — `tools/repl` (`nurl repl`)** (critic C1). An interactive
  read-eval-print loop on a process-per-eval model: top-level definitions
  (`@` functions, `&` FFI, `$` imports, and `:` types / enums / globals)
  accumulate into a persistent session, while every other line is spliced
  into a fresh `main`, compiled with `./nurl.sh -O0`, and run — its stdout
  is echoed back. A new definition is validated by a fast `build/nurlc`
  frontend pass before it joins the session, so a typo never poisons later
  evaluations. Line editing + history come from `std/term.nu` (the B10
  work); on a non-tty (pipe / script) it falls back to plain buffered
  reads. All REPL chrome — prompts, acks, errors, `:help` — goes to
  stderr, so stdout carries only the evaluated program's output. Meta-
  commands: `:help`/`:h`, `:quit`/`:q`, `:defs`, `:reset`, `:save FILE`.
  Multi-line definitions are read until brackets balance. Build with
  `./tools/repl/build.sh`; smoke-tested by `compiler/tests/repl_smoke.sh`
  (definitions + globals persist across lines, a bad definition is
  isolated, stdout stays clean). Note: process-per-eval re-initialises a
  `:` global on every evaluation — definitions and pure functions persist,
  but mutation does not accumulate across lines.

- **Bitset — `stdlib/std/bitset.nu`** (critic B18, collections round-out).
  A fixed-size bit array over 64-bit limbs: `bitset_set` / `bitset_clear`
  / `bitset_flip` / `bitset_test` (all bounds-checked, so the unused high
  bits of the last limb stay clear), `bitset_set_all` / `bitset_clear_all`,
  a popcount-backed `bitset_count`, `bitset_any` / `bitset_all` /
  `bitset_none`, the in-place combiners `bitset_and_with` / `bitset_or_with`
  / `bitset_xor_with`, `bitset_clone`, and an ascending `bitset_each_set`.
  Storage is a flat `nurl_zalloc` word buffer peeked/poked by limb. NURL
  has no native XOR or NOT operator, so the module uses the exact,
  carry-free identities `a ^ b = (a|b) - (a&b)` and `~m = -1 - m`. Lock:
  `compiler/tests/bitset_basic.nu` — cross-limb set/clear/flip, out-of-
  range no-ops, popcount, `all()` on a full set, the three combiners with
  an XOR-identity bit check, and clone independence; ASan+UBSan+LSan clean.

- **LRU cache — `stdlib/std/lru.nu`** (critic B18, collections round-out).
  A fixed-capacity `LruCache [V]` over string keys, backed by a HashMap
  (key → slot) plus an intrusive doubly-linked recency list over
  preallocated slot arrays with a free list — so `lru_get` / `lru_put` /
  `lru_contains` / `lru_remove` are all O(1) and a cache at capacity does
  no further allocation. `lru_get` moves the key to MRU; `lru_peek` does
  not; `lru_put` returns the displaced value (replaced or evicted), owned;
  `lru_each` walks MRU→LRU; `lru_free_with` drops each value on teardown
  (the owned-element discipline the deque/heap work established). The map's
  hash/eq closures are non-capturing, so they allocate nothing per call.
  Lock: `compiler/tests/lru_basic.nu` — eviction order, get-as-touch
  survival, peek-without-reorder, replace-returns-old, remove, the MRU→LRU
  walk, and the owned-String `free_with` path; ASan+UBSan+LSan clean. With
  the B-tree and bitset, this **closes critic B18**.

- **B-tree ordered map — `stdlib/std/btree.nu`** (critic B18). A
  `BTree [K V]` with O(log n) insert / lookup / delete, replacing the
  array-shift backing for large ordered maps. Classic CLRS proactive
  split-on-descent and borrow/merge-on-descent (minimum degree 8, so up
  to 15 keys per node) keep the tree balanced; each node also caches its
  subtree size, which makes `btree_key_at` / `btree_val_at` order-
  statistic queries (the *i*-th smallest key) O(log n) too. API:
  `btree_new` / `btree_len` / `btree_is_empty` / `btree_get` /
  `btree_contains` / `btree_set` / `btree_remove` / `btree_min_key` /
  `btree_max_key` / `btree_key_at` / `btree_val_at` / `btree_each` /
  `btree_free` / `btree_free_with`. Nodes are raw 6-slot blocks with
  typed-pointer access (the same generic-container pattern as
  `std/set.nu`). Lock: `compiler/tests/btree_basic.nu` — a 2000-key
  scrambled fill with replace, remove-every-third churn, order-statistic
  and ascending-iteration checks, and full drain; ASan+UBSan+LSan clean.

- **Terminal control — `stdlib/std/term.nu`** (critic B10). The
  prerequisite for a REPL and TUI examples: POSIX termios raw mode
  (`term_raw_enable` / `term_raw_disable`, with `struct termios` sized
  via `nurl_native_sizeof` so the platform layout never leaks into NURL),
  `term_is_tty`, a full set of byte-exact ANSI builders (`ansi_reset` /
  `ansi_sgr` / `ansi_fg` / `ansi_bg` / `ansi_clear` / `ansi_clear_line` /
  `ansi_cursor_to` / `ansi_cursor_up`/`down`/`right`/`left`), and a
  minimal raw-mode line editor (`term_read_line`) with printable insert,
  backspace, ←/→, ↑/↓ history, Ctrl-A/E/K, and a clean not-a-tty None
  fallback. Adds `TCSANOW` / `TCSAFLUSH` to the runtime's
  `nurl_native_constant` table (POSIX-only; Win32/WASI return None from
  raw mode while the ANSI builders still work — Windows Terminal speaks
  VT). Lock: `compiler/tests/term_basic.nu` — the tty-independent surface
  (None on a file fd, byte-exact ANSI hex); ASan+UBSan+LSan clean.

- **ZIP archives — `stdlib/ext/zip.nu`** (critic B15). A reader and
  writer for the ZIP format over the existing zlib FFI. Writer: `zip_new`
  / `zip_add` (raw-deflate, windowBits −15, falling back to *store* when
  deflate would not shrink the entry) / `zip_add_stored` / `zip_finish`,
  emitting local headers, the central directory, and the EOCD with a
  fixed DOS timestamp so archives are byte-deterministic. Reader:
  `zip_open` (backward EOCD scan over the comment window, with zip64
  rejected as unsupported) / `zip_count` / `zip_name_at` / `zip_size_at`
  / `zip_extract` / `zip_extract_name` / `zip_close`, every extraction
  CRC-32-validated. Lock: `compiler/tests/zip_basic.nu` — build (deflate
  + store + a compressible 5000-byte entry), re-open, CRC-checked extract
  of each entry, by-name extraction, missing-name and junk-archive
  rejection; cross-checked against system `unzip -t`; ASan+UBSan+LSan
  clean.

- **SMTP client — `stdlib/ext/smtp.nu`** (critic B17). A mail-submission
  client over the runtime's client-side TCP/TLS connect: `smtp_connect` /
  `smtp_connect_tls`, EHLO capability discovery (`smtp_ehlo` /
  `smtp_has_cap`), `smtp_starttls` (RFC 3207 — upgrades the live
  plaintext fd to TLS and re-EHLOs), `smtp_auth_plain` / `smtp_auth_login`
  (RFC 4954), the `smtp_mail_from` / `smtp_rcpt_to` / `smtp_data`
  envelope (DATA dot-stuffs and terminates per RFC 5321 §4.5.2),
  `smtp_quit` / `smtp_close`, plus a minimal RFC 5322 MIME builder
  (`mime_build`), `smtp_dotstuff`, and `smtp_date_now`. STARTTLS needs to
  upgrade an already-open fd, which the existing connect primitives could
  not do, so this adds `nurl_tcp_starttls` to the runtime — the
  client-handshake half of `nurl_tcp_connect_tls` applied in place. Lock:
  `compiler/tests/smtp_basic.nu` — the offline surface (multiline reply
  scanner/parser, AUTH PLAIN/LOGIN base64 tokens, dot-stuffing, MIME),
  ASan+UBSan+LSan clean; `examples/smtp_send.nu` demonstrates the live
  STARTTLS submission flow.

- **Unix domain sockets — `stdlib/std/unixsock.nu`** (critic B9). The
  local-IPC sibling of `std/net.nu`'s TCP, same API shape but a
  filesystem path instead of host:port — for Postgres-over-socket,
  systemd-style services, container control planes. `unix_listen` /
  `unix_accept` / `unix_connect` / `unix_socketpair` / `unix_read_chunk`
  / `unix_write_all` / `unix_write_str` / `unix_close_conn` /
  `unix_close_listener` (which unlinks the socket file). Pure libc FFI
  (blocking SOCK_STREAM); `unix_listen` unlinks any stale path before
  binding. Adds `AF_UNIX` / `SOCK_STREAM` / `EADDRINUSE` to the runtime's
  `nurl_native_constant` table (POSIX-only; the module degrades to a
  clean `UnixSocket` error on Win32/WASI). Lock:
  `compiler/tests/unixsock.nu` — a deterministic `socketpair` round-trip
  (both directions + EOF-after-close) plus a thread-driven
  listen/accept/connect echo gated on `NURL_NET_TESTS`; ASan+UBSan+LSan
  clean on both paths.

- **CBOR (RFC 8949) — `stdlib/ext/cbor.nu`** (critic B16). The
  IETF-standard binary serialization (COSE / WebAuthn / CTAP), sibling of
  MessagePack, over the shared `Json` value: `cbor_encode Json →
  !( Vec u ) CborErr` and `cbor_decode ( Vec u ) → !Json CborErr`. Encode
  is canonical-ish — integers and lengths use the shortest head, floats
  are float64 — so equal documents serialize to equal bytes. Decode is
  liberal: every definite-length head, signed/unsigned integers at all
  widths, and **float16 / float32 / float64** (the half-float decoder
  handles zero / subnormal / normal / inf / NaN). Byte strings, tags,
  indefinite-length items, and exotic simple values are rejected as
  `CborUnsupported`; `undefined` (0xf7) → `JNull`. Lock:
  `compiler/tests/cbor.nu` — Json round-trip with canonical-byte check,
  the RFC 8949 Appendix A decode vectors (integer boundaries, negatives,
  nested array/map, all three float widths), and every documented
  rejection; ASan+UBSan+LSan clean (error paths free the partial tree).

- **Arbitrary-precision fixed-point decimal — `stdlib/std/decimal.nu`**
  (critic B14, the last ROADMAP numeric gap). A `Decimal` is a `BigInt`
  coefficient × 10^-scale, so it is *exact* — `0.1 + 0.2` is `0.3`, not
  the binary-float `0.30000000000000004` — and never overflows. Exact
  `dec_add` / `dec_sub` / `dec_mul`; `dec_div a b scale` with an explicit
  result scale and **banker's rounding** (round half-to-even, the
  financial default); scale-agnostic `dec_cmp`; `dec_round` / `dec_rescale`
  / `dec_normalize`; `dec_from_string` (`"-12.340"`, `".5"`, `"42"`) and
  `dec_to_string`. Builds on the `bigint` div/rem from PR #100. Lock:
  `compiler/tests/decimal.nu` (exact `0.1+0.2==0.3`, the full
  half-to-even rounding table incl. negatives, division + div-by-zero,
  normalize, cross-scale compare; ASan+UBSan+LSan clean — every
  intermediate `BigInt` freed).

- **Playground: rendered stdlib API reference at `/stdlib-docs`**
  (`nurlapi`). The `nurldoc` library is now wired into the playground
  server: `/stdlib-docs` is an auto-generated index of every stdlib
  module (grouped by `core`/`std`/`ext`/`hal`), and `/stdlib-docs/<path>`
  renders one module's signatures + doc comments through
  `nurldoc_render` → the existing `md_to_html` + dark-theme doc chrome
  (the same presentation as the README/spec pages). Append `.md` for the
  raw Markdown. Closes the loop the C2 nurldoc PR opened — the "broad
  stdlib" is now browsable, not just greppable. Listed in the OpenAPI
  spec; live-verified end-to-end (index + module HTML + raw `.md`,
  ASan-clean).

- **`nurldoc` — Markdown API-doc generator** (critic C2). The stdlib's
  `//`-header + doc-comment discipline (90+ modules) was unrenderable;
  `nurldoc` extracts each module's header block, top-level declaration
  signatures (functions trimmed at their `{` body; types/enums/consts
  keep their full definition), and the doc comment above each, into
  Markdown. The render logic is an importable library
  (`stdlib/ext/nurldoc.nu`, `nurldoc_render content title → String`,
  brace-depth-aware so `:` locals inside bodies are never picked up);
  `tools/nurldoc/main.nu` is a thin CLI — `nurldoc <file.nu>` to stdout,
  or `nurldoc <src-dir> <out-dir>` to walk the tree with `fs_glob` and
  write one `.md` per module. Lock: `compiler/tests/nurldoc.nu`.

- **HTTP-date / RFC 2822 date parsing — `stdlib/std/time.nu`** (critic
  B13). The server formatted HTTP dates (`time_format_http`) but could
  not parse them; `http_date_parse` now accepts all three forms RFC 7231
  §7.1.1.1 requires — IMF-fixdate (`Sun, 06 Nov 1994 08:49:37 GMT`),
  obsolete RFC 850 (`Sunday, 06-Nov-94 08:49:37 GMT`, 2-digit year via
  the POSIX <70 pivot), and asctime (`Sun Nov  6 08:49:37 1994`) — for
  `If-Modified-Since` / `If-Unmodified-Since` / cookie `Expires`.
  `rfc2822_parse` handles the email `Date:` form with numeric `±HHMM`
  zones (`Mon, 02 Jan 2006 15:04:05 -0700`). Both return UTC seconds in
  the `!i ParseErr` shape (pair with `time_from_unix`), matching
  `time_parse_iso`. Lock: `compiler/tests/http_date.nu` — the three
  RFC 7231 spellings agree on the spec's own example (784111777), the
  RFC 2822 `-0700` case equals Go's canonical reference instant, plus
  round-trip and rejects.

- **JWT bearer-auth middleware — `stdlib/ext/http_jwt.nu`** (B5
  follow-through). `with_jwt_hs256 secret inner` / `with_jwt_eddsa
  pubkey inner` wrap a claims-aware handler
  (`( @ HttpResponse HttpRequest Json )`) and return the standard
  `( @ HttpResponse HttpRequest )` middleware shape, so they compose
  with `with_access_log` / `with_cors_default` / `router_handle`. A
  request runs the handler only with a valid `Authorization: Bearer`
  token; the verified payload claims are passed straight in (no
  re-parse, no header injection / spoofing surface, borrowed + freed by
  the middleware). Missing / invalid / expired / not-yet-valid tokens
  get a 401 with an RFC 6750 `WWW-Authenticate: Bearer` challenge whose
  `error=` / `error_description=` names the failure. Kept in its own
  module so the base `ext/http_auth.nu` stays free of the OpenSSL
  dependency `ext/jwt.nu` pulls in. Lock: `compiler/tests/http_jwt.nu`
  (valid/expired/tampered/wrong-key/missing × HS256 + EdDSA;
  ASan+UBSan+LSan clean).

- **Filesystem niceties + glob — `stdlib/std/fs.nu`** (critic B6 + B7).
  `fs_rename` (libc `rename`), `fs_copy_file` (64 KiB-chunk streaming, so
  large files copy in bounded memory), `fs_tempfile` (libc `mkstemp` →
  unique 0600 file, returns the path). `fs_glob` expands shell patterns
  against the tree: `*` / `?` / `[...]` (with `[a-z]` ranges and
  `[!...]`/`[^...]` negation) within a segment, `**` as a whole segment
  for recursive descent, the leading-dot rule (`*` never matches a
  dotfile; an explicit `.` does), absolute or relative patterns. Pure
  NURL over `dir_list`. Lock: `compiler/tests/fs_glob.nu` (every pattern
  class + rename/copy/tempfile against a built temp tree).

- **One URL parser — `stdlib/std/url.nu`** (critic B12). RFC 3986
  `scheme://[userinfo@]host[:port][/path][?query][#fragment]` into an
  owned `Url`, with bracketed-IPv6 hosts, `url_default_port` /
  `url_port_or_default` (http/https/ws/wss/ftp/redis/postgres),
  `url_request_target` (path?query for the request line), a percent
  codec (`url_percent_encode`/`_decode`), and `url_query_decode` →
  `Vec[UrlParam]` (form-urlencoded `+`→space, `%xx`). Lives in `std/`
  with core-only deps so `ext/` layers on it without a cycle. Locked
  against RFC 3986 component-split vectors in
  `compiler/tests/url_parse.nu`.

- **JSON Web Tokens — `stdlib/ext/jwt.nu`** (critic B5). HS256 (HMAC-
  SHA256) and EdDSA (Ed25519) sign + verify over the existing crypto
  block and base64url. `jwt_hs256_sign/verify`, `jwt_eddsa_sign/verify`,
  a `…_verify_at` core taking an explicit epoch `now` (deterministic;
  the wrapper uses the system clock), and `jwt_decode_unverified`.
  Validates `exp`/`nbf` time claims; the HS256 signature comparison is
  constant-time (`std/subtle.nu`). The HS256 path reproduces the
  canonical jwt.io reference token exactly and EdDSA is goldened against
  the RFC 8032 test key (Ed25519 signatures are deterministic) in
  `compiler/tests/jwt_basic.nu`. Adds `b64_url_encode_vec` /
  `b64_url_decode_vec` to `std/encode.nu` for binary, unpadded
  base64url (the signature segment).

### Changed

- **`ext/websocket.nu` and `ext/http2_client.nu` delegate URL parsing to
  `std/url.nu`** (critic B12 consolidation). Both hand-rolled
  scheme/host/port/path splitting; their `__ws_parse_url` /
  `__h2_parse_url` are now thin wrappers over `url_parse` that enforce
  the ws/wss and http/https schemes and map to the existing `WsUrl` /
  `H2Url` types — same public API, one parser underneath. The new parser
  also correctly stops the authority at `?`/`#` (the old scanners folded
  a query into the host when no path was present) and keeps the query in
  the request target.

### Fixed

- **CRDT replica ids must be globally stable** (`dist/crdt.nu`,
  `dist/replicator.nu`, `dist/identity.nu`). The chaos-simulation harness
  exposed silent state corruption: `PNCounter` stored increments in a dense
  vector merged **by position**, while `identity_of` handed out ids in local
  first-seen order, so every node called itself replica 0 — two distinct
  replicas collided into one slot and the merge took `max(1,1)=1` instead of
  summing to 2, converging to the *wrong value with no error*. Fixed deeply:
  `identity_stable_id(pubkey)` derives a globally consistent id from the pubkey
  (FNV-1a/64, no coordination); `PNCounter` is now sparse and **keyed by
  replica id** (merge aligns by identity, not position); the wire carries the
  id per slot and `pncounter_encode` emits slots in canonical ascending-id
  order so equal states encode identically (required by the digest anti-entropy).

- **Struct-pointer field access mis-resolved when the field name shadows a
  variable** (`compiler/nurlc.nu`, `gen_field`). `. p field` on a struct
  *pointer* resolved `field` as a same-named local integer and emitted a pointer
  array-index instead of a field load — a silent miscompile only `clang` caught.
  A struct field now always wins over a same-named variable on the field-load
  path (the field-*store* `= . p name val` array-index form is unchanged and
  intentional). Lock: `compiler/tests/ptr_field_name_shadow.nu`.

- **Closure literals rejected parenthesised compound param/return types**
  (`compiler/nurlc.nu`, `gen_backslash_expr`). `\ ( Vec u ) p → ( Vec u ) { … }`
  failed with “undefined identifier 'u'” because `\ (` was only treated as a
  closure when the next token was `@`; a compound type head fell through to the
  try-expression path. `\ (` is now a closure whenever the next token introduces
  a type (incl. the builtin `Vec`). Lock: `compiler/tests/closure_compound_param.nu`.

- **`@ ?Enum { T Variant }` emitted invalid IR** (`compiler/nurlc.nu`,
  `gen_agg_lit`). Constructing `Some(variant)` of an option whose
  payload is a no-payload (C-style) enum inserted the variant's bare
  i64 tag into the option's `%Enum` aggregate slot, which clang
  rejected (`insertvalue operand and field disagree in type`). The
  Result form `! T E` always worked because its payload slot is i64;
  only the option payload field carries the full `%Enum` type. The
  coercion now wraps the tag with `insertvalue %Enum zeroinitializer,
  i64 tag, 0`. Found while writing `ext/jwt.nu`. Lock:
  `compiler/tests/option_enum_payload.nu`.

- **Cryptography block — AEAD, signatures, key exchange, KDFs**
  (`stdlib/ext/crypto.nu`, critic B1–B3). Binds libcrypto's EVP layer
  through pure-NURL `` & `openssl` @ `` FFI (no C bridge, same sentinel
  pattern as TLS/libpq → "install libssl-dev" at compile time):
  AES-256-GCM and ChaCha20-Poly1305 one-shot AEAD (tag appended;
  `CryptoVerify` on tampered input); Ed25519 keygen/sign/verify and
  X25519 keygen/derive via the EVP_PKEY raw-key API; HKDF-SHA256,
  PBKDF2-SHA256/512, and scrypt. Every primitive is locked against its
  published vector (NIST GCM, RFC 8439, RFC 8032 §7.1, RFC 7748 §6.1,
  RFC 5869 A.1, RFC 7914 §12) in `compiler/tests/crypto_evp.nu`.
- **`std/subtle.nu` — constant-time comparisons** (critic B4).
  `constant_time_eq` / `_eq_n` / `_eq_vec` for secret material,
  promoted from the private bearer-token loop in `ext/mcp_registry.nu`
  (which now calls it). Length-leaking but content-timing-invariant,
  matching `hmac.compare_digest` / Go `crypto/subtle`.

### Fixed

- **`ext/crypto.nu` HKDF: binary salt was silently zeroed** before the
  module shipped — `nurl_str_get` is a NUL-bounded C-string read, so
  hex-encoding a `Vec u` salt through a `# s` cast truncated at the
  first `0x00` byte. Switched the binary→hex helper to the `*u` + `. p k`
  indexed load (the idiom `encode.nu`'s `__b64_emit` already uses). The
  RFC 5869 test vector caught it; documented as a reuse hazard in
  `critic.md` B3.

- **`nurlc --lint` detects unused imports** (`compiler/nurlc.nu`). A
  top-file `$` import none of whose defined symbols (functions, FFI
  externs, types, constants — generic templates included) is referenced
  by the top file itself now warns `unused import: no symbol from
  '<path>' is referenced in this file`. References count from calls,
  identifier reads, and type positions; uses recorded while re-parsing
  generic template bodies during the instantiation flush are attributed
  to the template's defining file, so stdlib internals never mask a top
  file's dead import. Pure aggregator files (only `$` directives, no
  decls of their own — e.g. `stdlib/ext/http_full.nu`) are exempt both
  as importer and as import target: re-exporting is their purpose. The
  LSP server (v0.6.0) now surfaces these straight from `nurlc --lint`
  and drops its former text-heuristic duplicate (~190 LOC removed) —
  one source of truth for the diagnostic.

- **Unknown callees are compile errors now** (`compiler/nurlc.nu`). A
  call to a name with no registered return type — not an `@`-fn, FFI
  extern, builtin, impl method, or local closure — previously fell
  through as an assumed-`i64` call to an undeclared symbol: invalid IR
  that clang rejected far from the source, or worse, code that linked
  by accident when the defining file happened to be imported later in
  the unit *and* the return type happened to be i64. Now dies at the
  call site: `call to unknown function 'X' — … add the missing '$'
  import … or check the spelling.` Same treatment for a generic call
  whose template is nowhere in the import closure (was: opaque
  `expected '->' but found end of input` inside the synthetic
  `<generic …>` source). En route this surfaced — and forced fixing —
  nine runtime builtins that were header-declared but missing from the
  compiler's symbol table (`nurl_peek`, `nurl_init`, `nurl_memset`,
  `nurl_vec_drop`, `nurl_argc`, `nurl_argv_count`, `nurl_read_int`,
  `puts`, `printf`), all silently riding the i64 default.

### Fixed

- **180 stale `$` imports removed tree-wide** (88 stdlib, 92
  tests/examples/tools). Several masked real latent bugs, now fixed
  with explicit imports: `stdlib/ext/csv.nu` used `opt_unwrap_or`
  without importing `stdlib/core/option.nu` (rode on `sort.nu`'s own
  stale import), `stdlib/ext/http2_hpack.nu` called
  `h2_default_header_table_size` without importing
  `stdlib/ext/http2_frame.nu`, and `stdlib/std/bufio.nu` called
  `nurl_file_open`/`nurl_file_close` without importing
  `stdlib/std/fs.nu` — each compiled only when every consumer
  happened to import the missing file first. `stdlib/std/set.nu` no
  longer imports `hashmap.nu` for its callers' convenience; import it
  alongside (the stock `hash_*`/`eq_*` helpers live there).

## [0.9.7] — 2026-06-11

### Added

- **Enum payload residuals diagnosed — ghost variants and unsized
  generics are hard errors now** (`compiler/nurlc.nu`, critic A7).
  An unknown/unimported type name in an enum variant's payload position
  parses as a SEPARATE variant (same-file forward references already
  resolve via the pre-scan, so this fires only for typos and missing
  imports) — the intended payload silently vanished and downstream
  code emitted out-of-bounds `extractvalue` / broken `store` IR, or
  silently read a sibling variant's slot. Three new hard errors:
  payload-arity checks at the match arm ("match arm binds 1 payload(s)
  but variant 'V' declares only 0 …") and at the enum literal, both
  naming the unknown-type-parses-as-variant cause; and an
  unknown-generic check in `parse_type_paren` — `( Vec i )` with no
  generic-struct template in scope and no materialised instantiation
  dies at the use site naming the missing `$` import, instead of
  clang's "loading unsized types is not allowed" far from the cause
  (zero-type-arg `( Type )` trait-impl targets are exempt). Locks:
  `should_fail_ghost_variant_match.nu`,
  `should_fail_ghost_variant_construct.nu`,
  `should_fail_unknown_generic_type.nu`. False-positive sweep: full
  suite 339 PASS + nurlapi + examples clean.

- **"Statement has no effect" warning — the last silent prefix-arity
  cascade is now diagnosed** (`compiler/nurlc.nu`, critic A2). A
  statement that produces a value without being a call or control flow
  (bare local identifier, operator expression like `+ a 1`, a `#` cast,
  a `.` field read) discards that value silently — under prefix
  notation with fixed arity and no closing token, this is exactly the
  residue left when an operator short an argument swallows the next
  statement's leading token. The bare-literal flavor was already a
  hard error (dangling operand); these shapes name real bindings, so
  they warn. Value-block tail expressions (the block result), calls,
  and `?`/`??` statements (their arms may be effectful) are exempt.
  The diagnostic embeds the dead statement's own line — by the time
  the block iterator sees the flag, the lexer already points at the
  next statement. Tree-wide false-positive check: nurlc.nu
  self-compile, the full stdlib, nurlapi, and examples produce ZERO
  warnings. Locks: `should_warn_dead_value.nu` (four dead shapes warn;
  tail/call/return stay silent), and `should_warn_caret_xor.nu` now
  also catches the previously silent dead `b` in `: i x ^ a b`. This
  closes the last undiagnosed half of the prefix-arity cascade family
  (critic §4); the A3 closing-delimiter decision can cite it as the
  mitigation.

- **`std/bigint`: arbitrary-precision division and modulo** —
  `bigint_div` / `bigint_rem` (`stdlib/std/bigint.nu`), closing the last
  gap in the bigint arithmetic surface. The magnitude core is Knuth
  Algorithm D (TAOCP vol. 2, §4.3.1) over the base-2¹⁶ limbs: D1
  normalization reuses the existing small-multiply helper (top divisor
  limb ≥ base/2, so every trial digit is off by at most one), the
  multiply-and-subtract step uses a per-limb {0,1} borrow (no negative
  shifts), and the rare add-back step is exercised by both classic
  Hacker's Delight `divmnu` trigger vectors. A single-limb divisor
  short-circuits through `__mag_divmod_small_inplace`. Semantics are
  truncated division exactly like the native `/` and `%`: the quotient
  rounds toward zero, the remainder takes the dividend's sign, and
  `x == (x/y)*y + x%y` holds for every `y ≠ 0`. Division by zero panics
  (recoverable via `recover`) — a defect, not a data error, so it is not
  threaded through `!`. Regression `compiler/tests/bigint_div.nu`: all
  four sign combinations, zero/`a<b`/exact edges, both add-back vectors,
  a 39-digit ÷ 21-digit case, a 60-round deterministic invariant sweep
  (reconstruction, `|r| < |y|`, remainder sign) over growing multi-limb
  operands, and the recovered divide-by-zero panic; ASan+UBSan clean,
  leak-free. Additionally verified against Python on 300 random cases
  (mixed limb counts/signs, near-power-of-2¹⁶ divisors).

### Fixed

- **Auto-drop: fn-returned by-value structs with owned fields now
  transfer ownership to the caller** (`compiler/nurlc.nu`, critic A4c).
  Two bugs closed. `^ @ T { ( nurl_str_cat … ) }` (direct construction
  return) leaked the field — the callee never bound it so never
  registered a drop, and the caller never registered one either.
  `^ v` where `v` is a bound struct was worse: a **use-after-free** —
  the callee's scope-exit drop freed v's owned field while the
  returned-by-value copy still aliased it, so the caller read freed
  memory. The fix mirrors the existing owned-string return flag: the
  callee skip-drops the escaping struct binding and publishes its exact
  owned-field list (`<fname>__ret_owned_fields`), which the caller's
  `: T x ( f )` re-registers through the same
  `mem_register_agg_owned_fields` path — exactly one drop, at the
  caller's scope exit. Ownership composes through `^ ( mk )` call chains
  and reaches nested struct fields. Safe against double-free with
  stdlib's manual `*_free` conventions: only raw-`s`/slice fields filled
  by a fresh allocation in a *direct* agg-literal return register for
  transfer — stdlib's struct returns use `String`/`Vec` handle fields
  (untracked) and build incrementally before `^ binding` (which never
  registers agg fields), so their manual frees stay correct. Verified:
  full san suite 0 SAN_FAIL, `tools/leakcheck` zero, suite 340 PASS,
  and a targeted incremental-build manual-free probe stays single-drop.
  Regression `ret_struct_owned_transfer.nu` (direct / bound / chain /
  nested shapes, ASan+LSan zero). No nurlc IR change — fixed point holds
  without a bootstrap refresh.


- **Auto-drop: arm-local trailing declarations leaked; `^ ( call )`
  string ownership now propagates; aliasing escapes transfer ownership**
  (`compiler/nurlc.nu`, critic A4). Three coupled fixes: (1) a `:`
  declaration as an arm's LAST statement made the arm look
  value-producing (gen_let_or_struct left the RHS type in last_type),
  which suppressed the Phase 2D fall-through drop — leaking the binding
  on every `?`/`??`/loop arm ending in a decl — and emitted a bogus phi
  over the discarded value; declaration statements now publish `void`.
  (2) `__fn_ret_str_owned__` was only set for identifier returns, so
  `@ helper → s { ^ ( nurl_str_cat … ) }` was never marked
  `__ret_owned=str` and `: s x ( helper )` leaked one buffer per call;
  gen_ret now consults the outermost call's `__last_call_ret_owned__`
  for direct parenthesised-call returns, making ownership compose
  through helper chains. (3) The widened tracking exposed missing
  ownership TRANSFER on aliasing escapes: `= outer x` and ternary/match
  arms whose value is a bare load of an owned binding now cancel that
  binding's scheduled drop (`mem_remove_owned_str`; the arm delta-drop
  protocol switched from prefix-length to word-membership to stay
  consistent under mid-list deletion). Conservative direction
  throughout: worst case a leak, never a use-after-free — the
  pre-transfer behavior freed buffers that had escaped through phis,
  which miscompiled the compiler itself (gen_cast's
  `: s norm ? … xv ( nurl_cg_reg cg )` returned a freed register
  name). Bootstrap snapshot refreshed (`--refresh-bootstrap`).
  Regressions: `arm_local_trailing_drop.nu` +
  `ret_owned_propagation.nu`, both ASan+LSan zero, with manual-free
  double-free locks on the transfer paths. Known residual filed as
  critic A4c: fn-returned structs with owned fields still transfer
  nothing (needs an ownership-model decision against the stdlib's
  manual `*_free` handle conventions).

- **`server_stop` from another thread freed the listener under blocked
  pool workers** (`stdlib/ext/http_server.nu`). `server_run_pool`'s
  documented shutdown — call `server_stop s` from another thread while
  workers block in accept — was a heap-use-after-free: workers hold no
  reference on the listener, so the stop's `nurl_tcp_close` dropped the
  last ref and freed the struct while every worker was still polling
  its `shutting_down` flag and wake-pipe fd (3/3 reproducible under
  ASan; single-threaded `server_run` raced identically). `server_run`
  and `server_run_pool` now retain the listener for the whole
  run→join window and release it only after no worker can touch the
  handle — the same contract `server_run_async` already followed for
  its accept fiber. The two-phase `tcp_shutdown_listener` → join →
  `server_stop` pattern remains valid; it is simply no longer the only
  safe shutdown. Regression `compiler/tests/http_server_stop_direct.nu`
  drives both fixed paths with a direct cross-thread stop (ASan-clean
  10/10 under `NURL_NET_TESTS=1`). Closes critic.md B19 together with
  the earlier accept-wake fix (f470571).

- **`recover` leaked the closure's captured environment**
  (`stdlib/std/panic.nu`). `recover` decomposes its closure into
  `(fn_ptr, env_ptr)` and hands them to the C trampoline; passing the
  raw env pointer onward suppresses the parameter's auto-drop (the
  compiler must assume the env escapes — and in `thread_spawn`, whose
  shape this mirrors, it really does). But `nurl_recover` is
  synchronous: once it returns, the closure can never run again, so the
  env was simply leaked — one allocation per `recover` call with a
  capturing closure, panic or not. `recover` now frees the env right
  after `nurl_recover` returns (NULL-safe for capture-less closures),
  on both the normal and the unwind path. Found via ASan on the new
  `bigint_div` divide-by-zero regression; the existing
  `recover_basic` / `http_server_panic` goldens are unaffected (output
  is unchanged — only the leak is gone).

- **HTTP/1.1 server hardening — four root-cause bug fixes from a focused
  security bughunt** (`stdlib/ext/http_request.nu`, `http_server.nu`,
  `http_response.nu`):
  - **Chunked request bodies were silently dropped on keep-alive
    connections.** `__finish_body` only handled `Content-Length`, so a
    `Transfer-Encoding: chunked` body was left undrained in the connection
    carry buffer — the handler saw an *empty* body and the leftover bytes
    were mis-parsed as the next request (a desync / request-smuggling
    vector). `__finish_body` now decodes chunked bodies carry-aware
    (draining from the buffer + socket, leaving any pipelined successor).
  - **Chunk-size integer overflow → smuggling/DoS.** `__parse_hex_size`
    accumulated an unbounded hex value; `0x10000000000000000` wrapped i64
    to `0` (read as the terminating chunk, ending the body early) or to a
    small positive (wrong boundary) — both smuggling vectors, and a huge
    positive could drive an enormous allocation. Now rejects any value
    past a sane ceiling, well clear of i64 overflow.
  - **Content-Length + Transfer-Encoding smuggling.** A request carrying
    both framing headers (RFC 7230 §3.3.3) is now rejected at head parse
    (and in `read_body_to`) instead of silently letting `Transfer-Encoding`
    win — the classic CL.TE desync.
  - **HTTP response splitting (CWE-113).** Response header names/values
    were serialised verbatim, so a value reflected from untrusted input
    (a redirect `Location`, an echoed header) could inject
    `\r\n<header>` and split the response. The serialiser (and the chunked
    `response_begin_chunked` path) now strips CR/LF from every emitted
    header name and value.

  Regressions: `compiler/tests/http_request_parser.nu` (CL+TE rejection,
  chunk-size overflow rejection), `http_response_builder.nu` (header
  CR/LF stripping), and a new live `http_server_chunked.nu` (chunked body
  decoded + keep-alive survives a chunked request, gated on
  `NURL_NET_TESTS=1`).

- **HTTP/2 client: request bodies larger than 256 bytes now work, and a
  large body no longer deadlocks the driver.** Three related fixes:
  - **SETTINGS parameter-ID mismap (critical).** The client's SETTINGS
    parser handled id `3` (`MAX_CONCURRENT_STREAMS`) as
    `INITIAL_WINDOW_SIZE` and ignored id `4` (the real
    `INITIAL_WINDOW_SIZE`), so every stream's send window was seeded with
    the peer's max-concurrent-streams value (typically 256) instead of its
    advertised window (65535). Any POST/PUT body over ~256 bytes stalled
    forever waiting for a WINDOW_UPDATE that never needed to come. IDs are
    now mapped correctly.
  - **Driver read/write interleave.** Each pump step now drains every
    inbound frame already available (readiness-probed via
    `nurl_reactor_wait_read`) *before* flushing pending DATA, keeping the
    peer's send buffer to us empty so it never blocks writing and keeps
    reading our DATA — removing the documented single-socket deadlock on a
    large request body.
  - **Server per-stream WINDOW_UPDATE** (`stdlib/ext/http2_conn.nu`). The
    h2 server replenished only the connection window, so it could not
    receive a request body larger than the 64 KB initial *stream* window;
    it now also replenishes each stream's window as it consumes DATA.

  Regression: `compiler/tests/http2_client.nu` gains a live 200 KB POST
  (spanning many DATA frames and several flow-control windows) over the
  in-repo h2 server, gated on `NURL_NET_TESTS=1`.

- **`inout` / `sink` parameter conventions now work on trait impl
  methods** (grammar-v2 borrow checker). An `inout` (or `sink`) parameter
  on an impl method silently miscompiled: the convention was recorded
  under the mangled method name (`bump__Counter`) while the call site
  dispatches by the bare name (`( bump c )`), so the receiver was passed
  **by value** into a `%T*` parameter — memory corruption / segfault.
  Fixing that surfaced a second bug (applying `inout` pointerised the
  first argument to `%T*`, which missed the `method##%T` impl-dispatch key
  and emitted an undefined bare `@method`). Both are fixed: the bare-name
  convention is mirrored at emission, and the impl-dispatch lookup retries
  with the receiver pointer stripped. Regression
  `compiler/tests/impl_inout_sink.nu` (struct `inout`, `inout` + by-value,
  a second implementing type, and a `sink` impl method; ASan + leak
  clean).

### Fixed (examples)

- **Game Boy emulator: deterministic ~90 s crash on Tobu Tobu Girl's
  title screen** (`examples/gameboy/core.nu`). Root cause was a
  halt-bug emulation error, found by stack forensics on an
  instruction trace: `EI` + `HALT` with a timer IRQ landing inside
  HALT's own 4-cycle window set `g_halt_bug`, the EI delay then raised
  IME and the interrupt dispatched immediately — and the stale
  halt-bug flag replayed the HANDLER's first instruction (PC failed to
  advance once inside the handler). Tobu's handler starts with
  `PUSH HL`, so SP skewed by 2 and `RETI` returned into WRAM data —
  the screen froze and execution fell into a RST 38 loop (the gray
  bars + hang seen on the playground). Two-part fix per Pan Docs:
  (1) `EI` immediately before `HALT` with a pending interrupt is NOT
  the halt bug — the interrupt is serviced with the HALT's own address
  as the return address; (2) invariant: an interrupt dispatch always
  clears the halt-bug replay (it applies to the next sequential fetch
  only, never the handler's). Verified: Blargg `cpu_instrs` 11/11 +
  `02-interrupts` + `instr_timing` still pass, dmg-acid2 renders, and
  a 40 000-frame idle soak (vs the ~2 918-frame crash) runs ASan-clean
  with a live framebuffer. Also: migrated `examples/gameboy` to the
  enforced `:` immutability (97 declarations — it sits outside the
  test suite, so the tree-wide migration missed it; all gameboy
  targets compile again, playground build regenerated), and fixed
  `gbtrace.nu --trace` to drive the real `cpu_advance` path (its
  hand-rolled step loop was a stale copy that never woke from HALT).

### Documentation

- **The `sink`-of-auto-dropped-value boundary is documented as an
  intentional, locked limitation** (`docs/MEMORY.md` §1,
  `docs/LIMITATIONS.md`). Passing a compiler-auto-dropped value (owned
  string / slice / `Drop` value / owned-field struct) to a `sink`
  parameter is rejected by design: the auto-drop obligation is tracked in
  per-scope owned-sets that are snapshotted/restored across `?` / `??` /
  loop boundaries, so transferring it to the callee would be silently
  undone by an enclosing arm's restore — reintroducing a double-free.
  Reframed from "a future step" to a sound, conscious 1.0 decision with
  the rationale and workaround; pinned by
  `compiler/tests/should_fail_sink_autodrop.nu`.

- **The `pub` visibility contract is now stated exactly and locked by
  tests** (`docs/spec.md` §3.3). Cross-file enforcement covers
  `@`-functions, structs, enums, top-level consts, and enum variants; `pub`
  on **traits, impl methods, and FFI** is accepted but has no cross-file
  effect *by design* — trait dispatch resolves by type-mangled method name
  (no trait-name identity to gate) and FFI symbols are linker-level ABI
  globals. New `compiler/tests/pub_trait_ffi_visibility.nu` pins the
  unenforced surface (a non-`pub` trait method + FFI stays callable across
  files) so it can't silently regress into enforcement; the existing
  `should_fail_pub_*` tests pin the enforced surface. (Corrects the stale
  "only `@`-function calls observe the check" wording.)

## [0.9.6] — 2026-06-08

### Added

- **HTTP/2 client — native, multiplexed (`stdlib/ext/http2_client.nu`).**
  Completes the HTTP/2 stack (server + client). Reuses the direction-neutral
  framing/HPACK: `h2_client_connect_tls` (TLS + ALPN `h2`) /
  `h2_client_connect_h2c` / `h2_client_attach` → `h2_client_submit` (N
  concurrent streams) → `h2_client_run_until_complete` →
  `h2_client_take_response`, plus one-shot `h2_get` / `h2_request`. Full HPACK
  (connection-global decoder), per-stream + connection flow control,
  WINDOW_UPDATE / SETTINGS / PING / GOAWAY / RST_STREAM. Added runtime
  `nurl_tcp_connect_tls_alpn`. Example `examples/h2_client.nu`.

- **MCP server: stateful sessions, SSE stream, and `sampling/createMessage`
  reverse RPC (`stdlib/ext/mcp_session.nu`).** The pure, socket-free stateful
  core: an `McpSessionStore` keyed by a CSPRNG `Mcp-Session-Id`, a per-session
  outbound notification queue, and server→client reverse-RPC correlation.
  `mcp_http.nu` gains `mcp_http_handler_session` (mints/validates session ids,
  drains the queue to SSE on GET, settles reverse-RPC responses, tears down on
  DELETE) plus chunked `mcp_sse_*` helpers for a long-lived stream.

- **MCP server: `completion/complete` argument autocompletion.**
  `mcp_registry_add_completion r ref_type ref_id handler` registers a
  completion provider for a prompt argument (`ref/prompt`) or resource template
  (`ref/resource`); `completion/complete` resolves it and returns the
  spec-shaped `{completion: {values, total, hasMore}}`. Unknown refs yield an
  empty list (per spec). Works over both stdio and HTTP transports.

- **MCP server: `resources/subscribe` + `notifications/resources/updated`.**
  Per-session resource subscriptions: `mcp_session_subscribe` /
  `_unsubscribe` / `_is_subscribed`, and `mcp_session_notify_resource_updated`
  which fans an update notification out to every subscribed session over the
  SSE queue. The session HTTP handler services subscribe/unsubscribe against
  the request's `Mcp-Session-Id`.

- **XML parser + serializer — `stdlib/ext/xml.nu`.** Parses the common subset
  (elements, attributes, nesting, self-closing, text, comments, CDATA,
  declarations, the 5 predefined entities + numeric refs) into an `Xml` tree;
  `xml_stringify` round-trips with entity encoding. Accessors + builders. Out
  of scope: DTD/DOCTYPE, namespace resolution.

- **YAML parser + serializer — `stdlib/ext/yaml.nu`.** Parses a pragmatic
  subset into the shared `Json` value (so every `json_*` accessor works on a
  parsed doc): block mappings/sequences, the seq-under-a-key idiom, plain and
  quoted scalars resolved per the YAML 1.2 core schema, flow collections,
  comments, `---`/`...` markers. `yaml_stringify` emits block style with
  round-trip-safe quoting. Out of scope: block scalars, anchors/aliases/tags,
  multi-doc streams.

- **Timezone / DST support in `stdlib/std/time.nu`.** Local-time conversion +
  DST driven by a POSIX TZ string (`EST5EDT,M3.2.0,M11.1.0`, `IST-5:30`, …) —
  the format IANA tzdata compiles each zone's current ruleset into (covers
  US/EU/AU). `tz_utc` / `tz_fixed` / `tz_parse` / `tz_offset_at` / `tz_is_dst`
  / `time_from_unix_tz` / `time_now_tz` / `time_to_unix_tz` /
  `time_format_iso_tz`. Not in scope: IANA region-name lookup.

- **Growing arena + typed allocation — `stdlib/std/arena.nu`.**
  `arena_growing chunk_sz` returns a chained-chunk arena: when the current
  chunk fills, a fresh chunk is linked in and old ones are never moved, so
  every pointer handed out before a grow stays valid (the canonical
  pointer-stable arena model). `arena_alloc_n [T] a count → *T` allocates
  `count` contiguous items of `T`. `arena_new` / `arena_with_cap` remain fixed
  (NULL on overflow) — byte-identical behaviour for existing callers.

- **Counting semaphore — `stdlib/std/thread.nu`.** `sem_new` / `sem_acquire`
  / `sem_try_acquire` / `sem_release` / `sem_avail` / `sem_free`, built on the
  existing `Mutex` + `Cond`. The permit count lives in a heap cell, so a
  by-value copy (e.g. a worker-closure capture) shares state across threads —
  the classic tool for bounding concurrency (see the nurlapi compile gate
  below).

- **`readlink(2)` FFI — `stdlib/std/fs.nu`.** `fs_readlink` reads a symlink's
  target as an owned `String` via a direct `& \`c\`` binding (no runtime
  change). `nurlpkg` now reads and verifies an existing `deps/<name>` link
  target, catching transitive name collisions.

- **Seedable, deterministic PRNG — `stdlib/std/rng.nu` (xoshiro256\*\*).**
  Companion to `std/random.nu`'s OS CSPRNG, which draws from the kernel
  entropy pool and *cannot be seeded*. `rng.nu` gives a reproducible stream:
  `( rng_seed s )` expands any i64 seed into a 256-bit xoshiro256\*\* state
  via SplitMix64 (so even `0`/`1` produce well-distributed, uncorrelated
  streams), and the same seed yields a **byte-identical sequence on every
  platform and build** — the determinism guarantee extends here because the
  generator is integer-only (no float state, `>>` lowers to a logical
  `lshr` on the `u64`-typed words). Surface: `rng_next` (raw 64-bit),
  `rng_below` (unbiased, rejection-sampled `[0,n)`), `rng_range`, `rng_u01`
  (uniform double in `[0,1)`, 53-bit), `rng_bool`, `rng_free`. Opaque-handle
  lifecycle (same shape as `Arena`/`Channel`/`String`); state mutates in
  place. **Not** a CSPRNG — predictable, so never for security; use
  `std/random.nu` there. Regression `compiler/tests/rng_seedable.nu` pins
  the exact stream for seeds `0` and `0x1234` against an independent
  reference implementation, and checks determinism, `rng_below` bounds, and
  the inverted-range guard.

### Changed

- **nurlapi: bound concurrent compiles to stop OOM crashes.** The container
  runs a 16-worker pool, so up to 16 requests run at once; each compile spawns
  `clang -O2 -flto` (hundreds of MB), and 16 simultaneously could exceed the
  container memory cap and get the whole process OOM-killed ("container is not
  listening"). The accept pool stays wide (light requests keep flowing) but the
  heavy compile step is now bounded by a counting semaphore: `POST /build*` and
  `POST /mcp` take a permit before dispatch and release after (panic-safe),
  default 4, tunable via `NURL_COMPILE_SLOTS`.

- **Reverse proxy: binary-safe streaming response bodies.** Streaming
  responses were forwarded via a NUL-terminated carrier and truncated at the
  first embedded NUL (only SSE/JSON/text survived). The proxy now reads the
  stream's true byte length and copies exactly that many bytes. New
  `bytes_extend_raw` + `http_stream_next_bytes` (→ `( Vec u )`).

- **ROADMAP.md rewritten** as a concise, forward-looking document (status →
  toward-1.0 → planned), with the per-feature history delegated to this
  changelog. Bootstrap snapshot refreshed.

### Fixed

- **Compiler: struct payloads in enum match slots 1 and 2.** A multi-field
  struct value carried as an enum payload anywhere but the first slot
  (`: | E { Nil  V  i Pt }`) emitted invalid IR (`store %Pt <ptr>`) and was
  rejected by clang — construction heap-boxed it for every slot but the
  match/unbox path only reconstructed slot 0. Slots 1/2 now mirror slot 0.

- **Compiler: recursive auto-`Drop` for boxed-payload enum trees.** A
  `% Drop`-free enum whose variants box struct/enum payloads now gets a
  compiler-generated recursive drop, so nested owned payloads are freed at
  scope exit instead of leaking.

- **Compiler: borrow provenance for auto-`Drop` enum bindings off a
  borrow-returning accessor.** A binding taken from an accessor that returns a
  *view* into its parent is no longer treated as owned, fixing a double-free.

- **Compiler: drop the scrutinee of `^ ?? owned { … }` that returns a
  scalar.** The owned match scrutinee in a returning `??` whose arms yield a
  scalar was leaked; it is now dropped before the return.

- **Compiler: reject unbalanced braces / stray top-level tokens.** Malformed
  brace nesting and stray tokens at top level are now hard errors with source
  locations instead of reaching the backend.

- **C64 emulator** correctness fix (`examples/`).

## [0.9.5] — 2026-06-04

### Added

- **Playground shows its deployed version, and the API auto-deploys on
  release tags.** The playground header now carries a version pill — a
  `__NURL_VERSION__` placeholder in `index.html` is stamped at image-build
  time from the `NURL_VERSION` build-arg (`dev` for local builds). A new
  `.github/workflows/api-deploy.yml` builds the API image on a `v*` tag (or
  manual dispatch), pushes it to Docker Hub under the exact semver
  (`nurllang/nurl:vX.Y.Z` — no `:latest`), pins `cloudflare/Dockerfile`'s
  `FROM` to that tag and runs `wrangler deploy`, so a git tag is now a
  reproducible playground release. The Docker image was renamed
  `hindurable/nurl` → `nurllang/nurl`; `registry-deploy.yml` is now
  manual-only (the registry changes rarely).

- **MQTT-over-WebSocket transport — `mqtt_connect_ws`.** Adds a WebSocket
  transport alongside the raw TCP/TLS path so a client can reach a broker's
  MQTT-over-WS endpoint (e.g. `wss://host:8084/mqtt`) — handy when a firewall
  only permits the WS port inbound. `wss://` enables TLS with certificate
  verification and negotiates the `mqtt` subprotocol automatically; the codec
  and framed packet reader stay transport-blind behind two chokepoints. New
  entrypoints `mqtt_connect_ws` / `mqtt_connect_ws_cfg`; `mqtt_disconnect`
  also sends a WS Close frame, and `mqtt_reconnect` rejects WS clients (no URL
  to redo the upgrade). `stdlib/ext/mqtt.nu`.

- **Package manager → MLP: login/search/info, yank, token-revoke, catalog UI
  (ROADMAP §4).** Rounds the registry out into a minimum *lovable* product.
  - **CLI ergonomics.** `nurlpkg login` stores a per-registry publish token
    in `~/.nurl/credentials` (chmod 600) — `publish`/`yank` resolve the token
    `$NURL_TOKEN` → credentials, so it no longer has to live in the
    environment. `nurlpkg logout [--revoke]` forgets it (and optionally
    revokes it server-side). `nurlpkg search <q>` and `nurlpkg info <name>`
    query the registry (`info` with no arg still prints the local manifest).
    New `stdlib/ext/credentials.nu`.
  - **Registry hygiene.** `nurlpkg yank|unyank <name> <version>` flips a
    version's yanked flag (owner-only, via `POST /api/v1/{yank,unyank}`); the
    resolver already skips yanked versions, so a yanked release disappears
    from resolution. `nurlpkg logout --revoke` (`POST /api/v1/revoke`) deletes
    the presented token from D1.
  - **Catalog UI.** The Worker's `/` is now a searchable package list and
    `/packages/<name>` a detail page (versions with yank state, latest
    dependencies, an install snippet); `GET /api/v1/search?q=` backs the CLI.
  - Client helpers: `pkg_search` (`pkg_fetch.nu`), `pkg_yank` / `pkg_revoke`
    (`pkg_publish.nu`). Regression `compiler/tests/credentials_basic.nu`
    (set/get/upsert/multi-registry/remove; gated `NURL_CREDS_TESTS=1`, clean
    under ASan/UBSan). Whole feature set verified end-to-end against the
    Worker under `wrangler dev`: login → creds-based publish → search → info
    → yank (install then fails ResolveNoMatch) → unyank → catalog → logout
    --revoke → publish rejected (PubAuth).

- **Transitive registry dependencies — `nurlpkg publish` sends `X-Nurl-Deps`.**
  Publishing now includes the manifest's registry dependencies (a JSON
  `[{name, req}]` built by `__deps_json`) as the `X-Nurl-Deps` header, which
  the registry records in the package index. `pkg_publish` gained a
  `deps_json` parameter. With the deps in the index, `resolve_registry`
  pulls **sub-dependencies transitively** — previously the index always
  recorded `deps: []`, so only leaf registry packages installed correctly.
  Verified end-to-end against the local Cloudflare Worker: publish `tdep-b`,
  publish `tdep-a` (depends on `tdep-b ^1.0`), then `install` a consumer of
  only `tdep-a` → both land in `deps/` and the lock. Registry now supports
  real dependency graphs. `stdlib/ext/pkg_publish.nu`, `tools/nurlpkg/main.nu`.

- **Package registry service — Cloudflare Worker + R2 + D1 (`registry/`,
  ROADMAP §4 phase 6).** The deployable server side of the ecosystem, in
  TypeScript. The read path serves the static `index/<name>.json` +
  content-addressed `pkgs/<name>/<name>-<v>.tar.gz` from R2 (cacheable, no
  compute); the write path `POST /api/v1/publish` authenticates a Bearer
  token (peppered SHA-256 looked up in D1), enforces **first-publisher name
  ownership** + **version immutability**, **recomputes the tarball SHA-256
  server-side** (never trusts a client digest), and writes the tarball +
  updated index to R2. Identity bootstraps via **GitHub OAuth** (`/login` →
  `/auth/callback` mints a one-time CLI token). D1 schema in
  `migrations/0001_init.sql` (users / tokens / packages / versions).
  Implements exactly the wire contract the NURL client already drives.
  **Validated end-to-end locally** (no Cloudflare account): under
  `wrangler dev` (miniflare R2 + D1), the real `nurlpkg` binary completes a
  full publish → install round-trip plus immutability (409) and bad-token
  (401) rejections — `registry/test-local.sh`. Ships with
  `registry/DEPLOY.md`, a `registry-deploy.yml` GitHub Actions workflow
  (guarded so a placeholder token can't trigger a broken deploy), and
  secrets kept out of the repo (`wrangler secret put` for
  `GITHUB_CLIENT_SECRET` / `TOKEN_PEPPER`; GH Actions secrets for the
  Cloudflare deploy token). This completes the registry-backed package
  manager: `nurlpkg publish` + `nurlpkg install` against a deployable
  registry, all pure-NURL on the client and standing up locally today.

- **Package publishing — `stdlib/ext/pkg_publish.nu` + `nurlpkg publish`
  (ROADMAP §4 phase 5).** The write side. `pkg_pack` walks a project tree
  into a `.tar.gz` (excluding `deps`, `.git`/dotfiles, `nurl.lock`,
  `target`, `build`); `pkg_publish` uploads it with `POST
  <registry>/api/v1/publish`, `Authorization: Bearer <token>`, and
  `X-Nurl-Package` / `X-Nurl-Version` headers (binary body via
  `http_request_bytes`), mapping status to PubAuth (401/403) / PubConflict
  (409, version immutability) / PubRejected. `nurlpkg publish` packs the
  current project, prints its size + SHA-256, and uploads using the token
  from `$NURL_TOKEN` and the registry from `$NURL_REGISTRY` →
  `[package].registry` → default; a missing token or any non-2xx exits
  non-zero. The registry recomputes the checksum server-side — no
  client-supplied digest is trusted. Regression
  `compiler/tests/pkg_pack_basic.nu` (offline pack + gunzip + tar_parse
  membership: nested source included, deps/ + dotfiles excluded), clean
  under ASan/UBSan + leak-free. Verified end-to-end against a static
  `python` registry: a full **publish → install round-trip** (a library
  packed, uploaded with a Bearer token, then resolved + installed into a
  consumer's `deps/`), plus immutability (409), bad-token (401), and
  no-token rejections. This is the exact contract the Cloudflare
  Worker + R2 write endpoint (phase 6) will implement.

- **Verified registry install — `stdlib/ext/pkg_fetch.nu` (ROADMAP §4
  phase 4b).** The I/O side that turns a resolved `LockPkg` into files on
  disk against a static-HTTP registry (R2 + CDN shape). `pkg_fetch_index`
  GETs `<registry>/index/<name>.json`; `pkg_install_one` downloads
  `<registry>/pkgs/<name>/<name>-<v>.tar.gz`, **verifies its SHA-256
  against the recorded checksum**, gunzips, and path-safe `tar_unpack`s it
  into `<dest>/<name>` — composing the whole pure-NURL package stack (http
  binary body + sha256 + gzip + tar). Capstone regression
  `compiler/tests/pkg_install_e2e.nu` stands up a **loopback NURL registry
  server** (serves a real `tar_create`+`gzip` tarball + an index carrying
  its true checksum) and drives the full pipeline resolve → download →
  verify → unpack end-to-end, plus a wrong-checksum rejection
  (PkgChecksumMismatch); `NURL_NET_TESTS=1`. Clean under ASan/UBSan.

  **`nurlpkg install` is now registry-aware.** It resolves the manifest's
  registry deps (`foo = "^1.2"` or `{ version, registry }`), downloads +
  verifies + unpacks each into `deps/<name>`, and writes a `nurl.lock`
  whose registry entries carry `source = "registry+<url>"` + the tarball
  `checksum` (path deps keep their local source). The registry URL comes
  from `$NURL_REGISTRY` → `[package].registry` → a built-in default. A
  failed download or checksum mismatch makes `install` exit non-zero.
  Verified end-to-end against a static `python -m http.server` registry
  serving a GNU-`tar --format=ustar | gzip` package (differential interop):
  the happy path installs + locks with the `sha256sum`-computed checksum,
  and a tampered index checksum is rejected with the package left
  uninstalled.

- **Binary-safe HTTP response body — `http_body_bytes` / `http_body_len`.**
  `http_body_str` reads the response body through a NUL-terminated carrier
  (truncates at the first embedded NUL). The new `http_body_bytes` returns
  an owned, length-accurate `( Vec u )` copy, and `http_body_len` exposes
  the byte count — required for binary downloads (package tarballs, images,
  compressed payloads). Completes the binary HTTP story alongside the
  earlier binary-safe request body. Regression:
  `compiler/tests/http_response_binary.nu` (loopback server replies a
  5-byte `A B \0 C D` body; client confirms full length + the NUL via
  `http_body_bytes`; `NURL_NET_TESTS=1`). Clean under ASan/UBSan.
  `stdlib/ext/http.nu`.

- **Registry resolution core — `stdlib/ext/registry_index.nu` +
  `stdlib/ext/resolver.nu` (ROADMAP §4 phase 4).** The read side of the
  package registry. A registry serves a static JSON index per package at
  `<registry>/index/<name>.json` (versions, each with a tarball SHA-256
  `checksum`, `yanked` flag, and `deps`); tarballs live at the
  content-addressed `<registry>/pkgs/<name>/<name>-<ver>.tar.gz`, so the
  whole read path is a cacheable CDN with no compute.
  `registry_index.nu` parses an index and `regindex_select` picks the
  highest non-yanked version satisfying a semver requirement.
  `resolver.nu`'s `resolve_registry` walks the transitive dependency graph
  (BFS) and emits a `Vec[LockPkg]` ready for `lock_serialize` — the index
  fetcher is injected as a closure (`name → index-JSON`), so resolution is
  pure and offline-testable; nurlpkg will wire it to an HTTP GET. v1 policy:
  one version per name (first requirement wins; a later one must share that
  version or it's ResolveConflict), sub-deps from the parent's registry,
  path deps left to the existing symlink installer. Regressions:
  `compiler/tests/registry_index_basic.nu` (parse + select + yanked
  exclusion + tarball URL) and `compiler/tests/resolver_basic.nu`
  (transitive resolve with a mock index, ResolveNoMatch, ResolveNotFound).
  Both clean under ASan/UBSan and leak-free.

### Changed

- **Signedness is now coupled to the value's type instead of a free-floating
  side-channel — the structural fix for the whole `u`-vs-signed-`i8` bug
  class.** The LLVM type (`i8`/`i16`/`i32`) can't distinguish NURL's unsigned
  `u`/`u16`/`u32` from the signed types, so signedness travelled in a
  separate `__last_unsigned__` syms entry that each of ~83 value-producing
  sites had to remember to update — and ~67 didn't, leaving a stale flag
  that silently sign- or zero-extended the next widen (the source of a long
  run of miscompiles). Now signedness lives in `g_last_unsigned_p` right
  next to `g_last_type_ptr`, and **`nurl_set_last_type` always resets it**
  (signed default): every value-producing site already calls the type-setter
  (IR needs the type), so a stale "unsigned" can no longer leak. The handful
  of unsigned-PRODUCING sites assert it atomically with the type via
  `nurl_set_last_type_u` / `nurl_mark_unsigned`, and widen/op-selection
  readers consult `nurl_last_unsigned`. This eliminated the stale-leak
  subclass structurally; the migration also surfaced and fixed a latent gap
  the old leaky channel had masked by accident — bitwise `&`/`|`
  (`gen_bitwise_binary`) never set its result's signedness, relying on the
  last operand's flag happening to survive. Net: fewer, simpler, faster
  (a global vs a string-keyed map) and no longer forgettable. Bootstrap
  fixed point holds; full suite + ASan/UBSan green; 500 fuzzer seeds clean
  across every dimension.

### Fixed

- **Two more silent unsigned-widening miscompiles** (same `__last_unsigned__`
  side-channel hazard; fixed in `compiler/nurlc.nu`). Regression
  `compiler/tests/const_ternary_signedness.nu` (7 known-answer checks).
  1. **An unsigned global const load sign-extended.** `# i GU` over
     `: u GU 200` gave −56. `gen_const_decl` now records `<const>__unsigned`
     (which `gen_ident` already turns into `__last_unsigned__` on load).
  2. **A `?` (ternary) result didn't carry its arms' signedness.**
     `# i ? c (# u 200) (# u 100)` sign-extended the selected value.
     `gen_cond` now snapshots each arm's `__last_unsigned__` and sets the
     result flag (the arms share a type, so either suffices).

- **A call to an unsigned-returning function sign-extended at the call
  site.** `# i ( f )` where `f → u` returns 200 gave −56 (and likewise for
  `u16`/`u32`): the call site never carried the callee's return signedness
  onto the `__last_unsigned__` side-channel the enclosing widening cast
  reads (the LLVM return type i8/i16/i32 can't distinguish `u` from `i8`).
  `scan_fn_sigs` now records `<fn>__ret_unsigned` in the persistent pre-pass
  symbol table (the per-function `gen_fn_decl` scope doesn't reach call
  sites), and `gen_call` re-asserts it on `__last_unsigned__` after the
  call. Regression `compiler/tests/fn_return_signedness.nu` (5 known-answer
  checks). Bootstrap fixed point holds; full suite + ASan/UBSan green.

- **Narrow sized-int enum payloads now compile and round-trip correctly.**
  An enum variant carrying a `u`/`i8`/`u16`/`i16`/`u32`/`i32` payload (e.g.
  `: | E { None Val u }`) was accepted by the front-end but emitted invalid
  IR: `gen_agg_lit` only converted i64/i32 payloads into the enum's pointer
  slot (so an i8 payload hit `insertvalue …, i8 …` against a `ptr` field —
  clang reject), and `gen_match` only un-converted i1/i64 (storing a `ptr`
  into an `i8` binding). Now construction widens a narrow payload to i64
  (zext for an unsigned payload, sext for signed — from the payload
  signedness `gen_enum_decl` now records) before `inttoptr`, and the match
  `ptrtoint`s back and truncs to the payload width, carrying the payload's
  signedness onto the binding so a later widen zero-extends an unsigned
  payload. Found by hand-probing the fuzzer's struct dimension outward.
  Bootstrap fixed point holds; full suite + ASan/UBSan green. Regression
  `compiler/tests/enum_payload_signedness.nu` (5 known-answer checks).

- **Two silent struct-field signedness miscompiles** (same fuzzer, extended
  with a struct dimension; same root cause — the LLVM field type can't carry
  NURL's signedness). Both fixed in `compiler/nurlc.nu`; regression
  `compiler/tests/struct_field_signedness.nu` (8 known-answer checks);
  validated by 600 fuzzer seeds with the struct dimension.
  1. **Reading an unsigned field sign-extended.** `# i . rec u8field` over a
     `u`/`u16`/`u32` field holding e.g. 200 read back −56: `gen_member` never
     surfaced the field's declared signedness onto `__last_unsigned__`.
     `gen_struct_decl` now records `<S>__<field>__unsigned`, and both the
     value (extractvalue) and pointer (GEP+load) field-load paths set the
     flag from it.
  2. **Constructing a wider field from a narrower unsigned value
     sign-extended.** `@ Wide { # u 130 }` into an `i64` field stored −126
     instead of 130 — `gen_agg_lit`'s field-store widening hardcoded `sext`.
     It now picks `zext` when the field value is unsigned (the
     `__last_unsigned__` snapshot it already takes), `sext` otherwise.

- **Two silent integer miscompiles, found by a new differential fuzzer
  (`tools/fuzz`) and fixed at the root in `compiler/nurlc.nu`.** Both
  produced wrong values with no error — the worst class of bug.
  1. **Unsigned-byte cast widening sign-extended.** `# i64 # u 217` gave
     −39 instead of 217: a nested cast-to-unsigned never set the
     `__last_unsigned__` side-channel the enclosing widening cast consults,
     so it defaulted to `sext`. `gen_cast` now records the cast target's
     signedness for an enclosing widen / binop / shift. (Previously only
     casts whose subject was a typed *binding* — where `gen_ident` sets the
     flag — widened correctly.)
  2. **Signed `i8` arithmetic treated as unsigned.** `gen_binary` inferred
     unsignedness from the LLVM type `i8`, but both the unsigned NURL `u`
     and the *signed* `i8` lower to LLVM i8 — so signed i8 `/ % >> <`
     selected `udiv`/`urem`/`lshr`/`icmp u*` and the result was marked
     unsigned, silently zero-extending a negative value at the next widen.
     Signedness now comes solely from the `__last_unsigned__` flag (set by
     `gen_ident` from a binding's `__unsigned` and by `gen_cast` from an
     unsigned cast target), never from the ambiguous LLVM type.
  Bootstrap fixed point holds; full suite + ASan/UBSan green. Regression
  `compiler/tests/cast_signedness.nu` (12 known-answer checks). Validated
  by 340 fuzzer seeds (0 divergences).

- **Three silent int↔float conversion miscompiles** (same fuzzer, extended
  with float round-trip + comparison + store-coercion probes; fixed in
  `gen_cast`). Same root cause — the LLVM integer type can't carry
  signedness, so it must ride the `__last_unsigned__` side-channel.
  1. **Unsigned int → float used `sitofp`.** `# f # u32 0x80000001` became a
     *negative* float (≈ −2.1e9 instead of +2.1e9); `# f # u 200` became
     −56. Now `uitofp` when the source is unsigned.
  2. **Float → int ignored target signedness.** Now `fptoui` for an unsigned
     target (a value above the signed max no longer becomes poison), else
     `fptosi`.
  3. **A float result leaked its source int's stale unsigned flag.** After
     `# i64 # f # u …`, the still-set `__last_unsigned__` made a surrounding
     `*`/`/` pick `udiv` on a negative product (e.g. `−65 / 7` computed as
     an unsigned divide → garbage). Float-producing casts now clear the
     flag; float→int casts set it from the target. Regression
     `compiler/tests/cast_int_float.nu` (9 known-answer checks). Validated by
     600 fuzzer seeds with the new float dimension (0 divergences).

### Added

- **Differential fuzzer for `nurlc` integer codegen (`tools/fuzz`).**
  `gen.py` generates random sized-integer expression trees and, from the
  same tree, both a self-checking NURL program (prints each result's exact
  64-bit pattern) and a Python reference oracle with explicit
  two's-complement / width / signedness semantics. `fuzz.sh` compiles each
  at `-O0` and `-O2` and requires `stdout(-O0) == stdout(-O2) == oracle`,
  catching miscompiles that are wrong at every optimisation level. Biased
  toward the historically fragile surface (width coercions, unsigned
  arithmetic, mixed signed/unsigned); generates no UB. Found and fixed two
  silent miscompiles on its first run (see Fixed, above). See
  `tools/fuzz/README.md`. Subsequently extended with `let`-binding store
  coercion, variable reuse, comparison operators, and int→float→int
  round-trips — which surfaced three more (see Fixed).

- **USTAR tar reader + writer — `stdlib/ext/tar.nu`.** Pure-NURL POSIX.1-1988
  tar: `tar_create` (entries → archive bytes), `tar_parse` (bytes → entries,
  in-memory), and `tar_unpack` (path-safe extract to disk). Composes with
  `gzip_compress`/`_decompress` to make the `.tar.gz` package format the
  registry will use. The reader treats archives as untrusted input:
  `tar_unpack` rejects absolute paths and `..` components (TarUnsafePath) and
  refuses symlink/hardlink/device members (TarUnsupported) so nothing can
  escape the destination; every header checksum is verified (TarBadChecksum)
  and an over-long declared size is TarTruncated. v1 supports the 100-byte
  `name` field on write (TarPathTooLong otherwise) and honours the `prefix`
  field on read. Bidirectionally interop-tested against GNU tar (NURL→`tar
  xf` and `tar cf`→NURL both round-trip). Regression:
  `compiler/tests/tar_basic.nu` (round-trip incl. embedded NUL in file data,
  gzip composition, checksum tamper, `../` rejection, unpack + binary
  read-back); verified clean under ASan/UBSan. First building block of the
  registry-backed package manager (ROADMAP §4).

- **Semantic Versioning 2.0.0 — `stdlib/ext/semver.nu`.** Pure-NURL semver
  parse / compare / render with full precedence ordering, including the
  prerelease rules (§11: numeric < alphanumeric identifiers, fewer < more
  identifiers, prerelease < release; build metadata ignored). Plus
  **version requirements**: `semver_req_parse` turns a constraint (`^1.2.3`,
  `~1.2`, `>=1.0`, `<2.0.0`, `=1.2.3`, `1.*`, `*`, or a bare `1.2.3`) into a
  half-open range, `semver_req_matches` tests a version, and
  `semver_req_max_satisfying` picks the highest matching version — the
  resolution primitive the registry-backed package manager needs (ROADMAP
  §4). Constraint dialect is **Cargo-shaped**: a bare `1.2.3` means `^1.2.3`,
  use `=1.2.3` to pin. v1 matches prereleases by pure range containment (no
  Cargo-style prerelease comparator special-casing yet). Regression:
  `compiler/tests/semver_basic.nu` (round-trip, the canonical §11 precedence
  chain, every constraint operator, `max_satisfying`, parse errors); clean
  under ASan/UBSan and leak-free.

- **Registry-ready manifest + typed lockfile.** `stdlib/ext/manifest.nu`'s
  `Dep` gained a `registry` field and `Manifest` gained a default
  `[package].registry`, so a dependency can now be expressed as a path dep
  (`{ path = "…" }`), a bare registry dep (`foo = "^1.2"`, default
  registry), or an explicit registry dep
  (`{ version = "1.0", registry = "…" }`); `dep_is_path` / `dep_is_registry`
  discriminate. New `stdlib/ext/lockfile.nu` is a typed view over
  `nurl.lock`: a `LockPkg { name, version, source, checksum }` with
  `lock_serialize` (deterministic, name-sorted, Cargo-shaped `[[package]]`
  blocks; `source`/`checksum` omitted for path/local packages) and
  `lock_parse` / `lock_load` (round-trips through `toml.nu`'s
  array-of-tables). `checksum` is the hex SHA-256 of the package tarball —
  the integrity pin a registry install verifies. Regressions:
  `compiler/tests/manifest_registry.nu`, `compiler/tests/lockfile_basic.nu`;
  clean under ASan/UBSan, leak-free. ROADMAP §4 phase 3 (data model for
  registry deps). `nurlpkg`'s two `Dep` construction sites updated for the
  new field.

- **WebSocket client (RFC 6455 §4.1 + §5.3).** `stdlib/ext/websocket.nu`
  gained the full client side to match the existing server. `ws_connect`
  / `ws_connect_with` parse a `ws://…` / `wss://…` URL, dial out (plain or
  TLS-with-cert-verification via the runtime client-connect primitives),
  send the HTTP Upgrade request with a fresh random `Sec-WebSocket-Key`,
  and validate the `101` response's `Sec-WebSocket-Accept`. Outbound frames
  are masked with a CSPRNG-drawn 4-byte key (`ws_client_send_text` /
  `_binary` / `_ping` / `_pong` / `_close`, `ws_client_write_frame`,
  `ws_serialize_frame_masked`); inbound server frames are read and required
  to be unmasked (`ws_client_read_frame` / `_read_message` /
  `_serve_messages`, which auto-pong masked). The frame reader/assembler is
  now shared between both directions via an internal `__ws_read_frame_ex` /
  `__ws_read_message_ex` parameterised on direction — no duplicated framing
  logic. Regression: `compiler/tests/websocket_client.nu` (RFC 6455 §5.7
  masked-frame byte vector, URL parsing, and a live `NURL_NET_TESTS=1`
  client↔server echo round-trip proving interop with the server stack).
  Example: `examples/ws_client.nu` (pairs with `examples/ws_echo.nu`).

- **Binary-safe HTTP request bodies — `http_*_bytes` family.** The s-body
  `http_request` / `http_post` / `http_put` family recovers the body length
  via `strlen`, so a request body with embedded NUL bytes (binary file
  uploads, MessagePack, protobuf) truncated at the first NUL. New
  length-carrying variants take the body as a `( Vec u )` and ship it via
  `CURLOPT_COPYPOSTFIELDS` + an explicit `POSTFIELDSIZE`, so the exact byte
  count is sent: `http_request_bytes` / `http_request_bytes_to`,
  `http_post_bytes`, `http_put_bytes`, and the streaming
  `http_stream_open_bytes_to`. The `body` argument is borrowed (the caller
  still owns it). Binary fidelity requires the libcurl backend; the
  WinHTTP/stub fallback round-trips through a NUL-terminated `s` and
  degrades to the old truncation. `stdlib/ext/http.nu`.

### Fixed

- **Reverse-proxy request body is now binary-safe + a latent use-after-free
  is closed.** `proxy_stream_to_conn_with` forwarded the upstream request
  body by converting the request's `( Vec u )` body to a NUL-terminated `s`
  and shipping it through `CURLOPT_POSTFIELDS` (strlen-sized), truncating
  binary uploads at the first NUL. Worse, the streaming opener set
  non-copying `CURLOPT_POSTFIELDS` and the proxy freed the body buffer
  *before* the first `multi_perform` read it — a dangling-pointer read that
  only escaped notice on small JSON bodies. Both are fixed by routing the
  length-tracked body through `http_stream_open_bytes_to`, which uses
  `CURLOPT_COPYPOSTFIELDS` (libcurl snapshots the bytes at open time, so the
  caller may free immediately and embedded NULs survive). Regression:
  `compiler/tests/http_binary_body.nu` (NURL client `http_post_bytes` of a
  5-byte `A B \0 C D` body to a loopback NURL server, asserting the server
  parsed all 5 bytes; `NURL_NET_TESTS=1`). Verified clean under ASan/UBSan.
  `stdlib/ext/http.nu`, `stdlib/ext/http_proxy.nu`.


## [0.9.4] — 2026-06-02

### Added

- **Keyword arguments — default parameter values + named call arguments.**
  A trailing parameter may carry a default: `@ f s a s b = `x` i n = 3 → R`
  (the default is a single source token — literal / const / atom). A call
  may then omit defaulted trailing arguments — `( f val )` — and/or pass
  arguments by name in any order, mixed with leading positional ones:
  `( f a: 1 b: 2 )`, `( f val n: 5 )`, `( greet greeting: `Hi` name: `Bob` )`.
  Implemented as a call-site desugaring to an ordinary positional call:
  `scan_fn_sigs` records each function's parameter names + default sources;
  `gen_call` fills omitted trailing defaults inline, and routes a call that
  uses `name:` labels through `gen_call_kwargs`, which evaluates arguments
  in source order and assembles them in parameter order. Existing positional
  calls take the unchanged path (byte-identical IR — bootstrap fixed point
  holds). Regression: `compiler/tests/kwargs.nu`. Current limits (documented
  in the grammar): not on generic functions, FFI/variadic, or parameters
  with the `inout`/`sink` convention; `**kwargs`-style collection is not
  provided (pass a `Json`/struct).

- **BLAKE3 hash (pure NURL) — completes the hash family.** New
  `stdlib/std/hash_blake3.nu` implements full BLAKE3 (the ChaCha-derived
  compression function, 1024-byte chunks split into 64-byte blocks with
  CHUNK_START/CHUNK_END flags, the binary Merkle tree of chaining values,
  and the ROOT-flagged final node), exposed via `blake3_bytes` /
  `blake3_hex` in `stdlib/std/hash.nu` (unkeyed, 32-byte output). All-NURL
  u32 wrapping arithmetic, little-endian, binary-clean over `( Vec u )` —
  **no C at all** (compiler and runtime untouched). Verified
  digest-for-digest against the official BLAKE3 reference across every
  structural path (empty, sub-block, the 1024-byte single chunk, the
  1025-byte two-chunk boundary, balanced multi-chunk trees up to 5000
  bytes); regression `compiler/tests/blake3.nu`; clean under ASan/UBSan/LSan.
  Closes the ROADMAP "Extended Hash Family" item — SHA-1/256/512, MD5,
  HMAC, and BLAKE3 are all shipped.

- **`volatile_load` / `volatile_store` compiler intrinsics for MMIO.** Emit
  `load volatile` / `store volatile` as pure IR (no runtime call, so they
  work on a freestanding target). The optimizer can no longer hoist an MMIO
  read out of a polling loop (LICM), reorder accesses, or coalesce repeated
  reads/writes — the missing piece for spinning on a device status register
  at `-O2`. The access width comes from the typed pointer argument (`*T`),
  so one pair covers i8/i16/i32/i64. `stdlib/hal/mmio.nu`
  (`mmio_read32`/`write32`/`set32`/`clear32`) now uses them, so the ESP32
  UART/GPIO drivers no longer need the `-O0` workaround. Regression:
  `compiler/tests/volatile_mmio.nu`; verified at `-O2` the volatile load
  stays inside the loop body.

- **ESP32 bare-metal register HAL (`stdlib/hal/esp32.nu`).** Pure-NURL GPIO
  and UART0 over the chip's memory-mapped registers (built on
  `stdlib/hal/mmio.nu`) — no ESP-IDF, no FFI. GPIO output enable / set /
  clear, and a blocking UART console (`esp32_uart_putc` / `getc` / `puts`
  with FIFO-count helpers), with register addresses taken from the ESP32 TRM
  and cross-checked against ESP-IDF's `soc/*_reg.h`. Demonstrated by the new
  fully-NURL UART echo example (`examples/esp32/idf-uart`).

- **C64 emulator example (`examples/c64`).** A MOS 6510 / Commodore 64
  emulator in pure NURL — a single `core.nu` engine shared by a native CLI
  and a WebAssembly browser front-end. The CPU core passes Klaus Dormann's
  `6502_functional_test` (the canonical 6502 correctness oracle, validated
  headlessly), and with stock KERNAL/BASIC/CHARGEN ROMs the machine boots
  through the full power-on sequence — PLA banking, CIA1 jiffy IRQ — to the
  BASIC `READY.` prompt.

### Fixed

- **nurlfmt split hex/binary/octal integer literals.** The tokenizer's
  numeric scanner stopped at the first non-decimal digit, so `0x3FF44008`
  became two tokens (`0` + identifier `x3FF44008`) and the reformatted
  source miscompiled — silently, because `--check` is idempotent on its own
  broken output. `tools/nurlfmt/tokenize.nu` now scans a `0x`/`0b`/`0o`
  prefix and its body as one token. Verified by the
  `nurlfmt_idempotent.sh` gate (450 files, IR-transparent) and by restoring
  the hex literals in the `examples/esp32/*` register maps that had been
  worked around with decimal constants.

- **SQLite production hardening (Tier 1 + Tier 2).** `stdlib/ext/sqlite.nu`
  is now binary-safe and resource-safe:
  - **NUL-safe text I/O.** `sqlite_column_text` reads the column's exact
    byte length via `sqlite3_column_bytes` (was `strlen`, which truncated
    at the first embedded NUL), and `sqlite_bind_text` now takes a `String`
    and passes an explicit byte length to `sqlite3_bind_text` instead of
    `-1` — strings with embedded NULs round-trip intact.
  - **BLOB support.** New `sqlite_bind_blob` (`Vec u` → `sqlite3_bind_blob`
    + `SQLITE_TRANSIENT`) and `sqlite_column_blob` (`sqlite3_column_blob` +
    `_bytes` → owned `Vec u`) — the binary-safe write/read path.
  - **`sqlite_open_v2` with open flags.** `SQLITE_OPEN_READONLY` /
    `READWRITE` / `CREATE` / `URI` / `NOMUTEX` / `FULLMUTEX` / `NOFOLLOW`
    constants exposed; `sqlite_open` is now `READWRITE|CREATE` over
    `open_v2`. A read-only connection refuses writes (new `SqliteReadOnly`
    error variant) instead of silently creating a file.
  - **`sqlite_busy_timeout`** wraps `sqlite3_busy_timeout` so `SQLITE_BUSY`
    blocks-and-retries under concurrent access rather than failing
    immediately.
  - **`% Drop` auto-close.** `Database` and `Statement` implement the Drop
    trait; a scope-local handle — including one unwrapped from a
    `! Database E` / `! Statement E` result in a match arm — closes itself
    on every path (Ok, Err, early return) with no manual
    `sqlite_close`/`sqlite_finalize`. Teardown zeroes the handle slot after
    closing, so a stale internal re-entry is a no-op. Verified leak-free
    and double-free-free under ASan + UBSan (`compiler/tests/sqlite_hardening.nu`).
  - **Tier 3 — datatypes & transactions.** `sqlite_bind_double` /
    `sqlite_column_double` (REAL columns), `sqlite_column_is_null`,
    `sqlite_begin` / `commit` / `rollback`, and a closure-based
    `with_transaction` that COMMITs on `Ok` and ROLLBACKs on `Err`
    (propagating the original error).
  - **Tier 4 — hardening for untrusted SQL/DB.** Extended result codes are
    enabled on every open, so constraint failures now map to distinct
    variants (`SqliteConstraintUnique` / `…ForeignKey` / `…NotNull` /
    `…PrimaryKey` / `…Check`). Added `sqlite_last_insert_rowid`;
    `sqlite_set_defensive` / `sqlite_enable_load_extension` /
    `sqlite_harden` (DEFENSIVE on + extension-loading off — blocks
    corruption/RCE from a hostile DB); `sqlite_limit` (bound query
    complexity); a closure-based `sqlite_set_authorizer` /
    `sqlite_clear_authorizer` that installs a sandbox callback with the
    exact C ABI libsqlite expects (the closure's compiled function +
    captured env are passed as `xAuth` + `pUserData`, the same mechanism
    `thread_spawn` uses for `pthread_create` — no C bridge); and PRAGMA
    helpers `sqlite_journal_wal` / `sqlite_foreign_keys` /
    `sqlite_synchronous`. Verified under ASan + UBSan
    (`compiler/tests/sqlite_tier34.nu`).

### Changed

- **Match-arm payload bindings now participate in auto-drop.** A `% Drop`
  type bound as a `??` match-arm payload (e.g. `?? r { T db → … }`) — or a
  `:` let inside a match arm — is now dropped at arm scope exit, on the same
  void-arm-only rule used for owned strings/structs. Previously such
  bindings were never dropped (a latent leak); this is what lets the SQLite
  handles above close automatically in the idiomatic result-unwrap flow.

### Documentation

- **ROADMAP brought up to date.** The Status header now reads **Grammar v2.1**
  (was v2.0) and points at `spec/grammar.ebnf`. Items that were marked pending
  but are in fact shipped are now `[x]`: the **async runtime** (stackful M:N
  fibers — the Coroutines-vs-async/await decision is settled), **HTTP server
  Phase 8** (production hardening) and **Phase 9** server-side (TLS+SNI+ALPN+
  mTLS+reload, HTTP/2, WebSocket — client-side remains), the **optional
  `-lcurl`** sentinel-gated linking, and the **`nurlc_lastgood.nu` refresh**
  lifecycle (documented via `--refresh-bootstrap`). Added an explicit
  "What's actually left" summary to the Status section (HTTP/2+WebSocket
  client-side; mobile/`no_std` targets; SQLite BLOB/double; reverse-proxy
  binary bodies; blake3; MCP SSE/sessions/auth; the `runtime.c` file-split;
  a compiler-embedded LLM; bench peers). Stale build-size figures left only
  in dated historical "shipped" entries (records, not current claims).

- **Removed hard-coded build-artifact sizes from the reference docs.** The
  `~480 KB nurlc.wasm` (`docs/PLAYGROUND.md`) and `~1.6 MB`
  `nurlc_lastgood.ll` (`docs/BUILDING.md`) figures drift every build and
  mislead when the real artifact differs. Build sizes belong in the
  changelog/release notes (tied to a specific version), not in
  instructional docs.

- **Cleaned stale `GOTCHAS.md item N` / `§N` references out of code comments.**
  After `docs/GOTCHAS.md` lost its numbered list, ~44 source comments (in
  `compiler/nurlc.nu`, the `nurlc_lastgood.nu` snapshot mirror, nine
  `compiler/tests/*.nu`, and `stdlib/ext/{http_middleware}.nu`) still pointed
  at item/section numbers that no longer exist. Each now points at the real
  home (escape/lifetime → `docs/MEMORY.md` §2.3, grammar → `docs/LIMITATIONS.md`)
  or simply describes the behaviour inline. The `nurlc_lastgood.nu` edits are
  comment-only — verified to produce byte-identical IR, so the committed
  bootstrap `nurlc_lastgood.ll` is unchanged; the build still reaches its
  fixed point and the full test suite passes.

- **`docs/GOTCHAS.md` reduced to "Currently no known gotchas."** Every
  source-level trap is now a compiler diagnostic (`error:`/`warning:` with a
  caret + cure), so the page no longer lists a museum of resolved issues.
  The real content that lived there was relocated to its proper home: the
  fiber-runtime operational caveats (non-blocking handle flipping,
  `runtime_run` blocking, stack-borrow capture, plus runtime-maintainer
  notes on TLS-under-LTO and the reactor park/unpark ordering) moved to
  [`docs/ASYNC.md`](docs/ASYNC.md) → Operational caveats, and the
  `: ~`-capture lifetime rule now points at [`docs/MEMORY.md`](docs/MEMORY.md)
  §2.3. Updated every back-reference (`docs/spec.md`, `docs/LIMITATIONS.md`,
  `ROADMAP.md`'s "5 active quirks" status line, the VS Code extension
  README, and stale `GOTCHAS.md item N` comments in `stdlib/ext/toml.nu`,
  `mcp_http.nu`, `http_multipart.nu`). All internal links verified.
- **`docs/LIMITATIONS.md` scoped to actual language/compiler limitations.**
  Removed the standard-library capability tables (PostgreSQL, SQLite,
  panic/recover) that were never language limitations — that information
  lives with each module (stdlib headers, `ROADMAP.md`, `TODO.md`). Moved
  the HTTPS/TLS table to [`docs/NETWORKING.md`](docs/NETWORKING.md) where it
  belongs. Removed two entries that were **stale** (the behaviour already
  works, verified empirically): "no tail-call optimisation" (self-recursive
  tail calls emit `tail call` → LLVM sibcall-opt; 50M-deep tail recursion
  runs without overflow) and "enum forward references unsupported"
  (`scan_type_names` registers type names before codegen, so a struct
  payload can be declared after its enum). The page now lists only
  language/compiler constraints (Type system, Functions/calls, Enums,
  Imports, Grammar).
- **Playground now renders linked docs instead of 404ing.** Clicking a
  relative link inside a rendered doc (e.g. `docs/LIMITATIONS.md` from the
  README, or `../spec/grammar.ebnf` from a `docs/` page) used to hit "not
  found". `nurlapi` now serves the repo doc tree by its natural path —
  `/docs/*`, `/spec/*`, `/bench/*`, and the capitalised top-level
  `/README.md` · `/ROADMAP.md` · `/CHANGELOG.md` · `/CONTRIBUTING.md` —
  rendering `.md` to HTML (`__serve_repo_doc`, path-traversal-guarded) and
  serving other files as text; `examples/*.md` renders too (`.nu` stays
  JSON for the editor). Because the route hierarchy mirrors the repo, the
  browser's own relative-link resolution chains correctly between docs. The
  container image now copies the **whole `docs/` tree** (was only
  `GOTCHAS.md`) plus `CHANGELOG.md`, `CONTRIBUTING.md`, and `bench/`.
- **README refactored into a slim overview + topic docs.** The 991-line
  kitchen-sink README is now a ~230-line overview (why/principles,
  architecture, quick start, syntax-at-a-glance, a documentation index, and
  project layout) that links out to focused pages under `docs/`. New:
  `docs/BUILDING.md`, `docs/TOOLING.md`, `docs/PLATFORMS.md`,
  `docs/PLAYGROUND.md` (HTTP API + playground + MCP), `docs/NETWORKING.md`
  (sockets + MQTT), `docs/LIMITATIONS.md`. Syntax/type/memory sections now
  point to the existing authoritative homes (`spec/grammar.ebnf`,
  `docs/spec.md`, `docs/MEMORY.md`) instead of duplicating them.
- **Removed stale / frequently-changing content.** The README no longer
  hard-codes a grammar version, benchmark tables (point to `bench/`), the
  example file list, the MCP tool count, or the `.vsix` version. The
  PostgreSQL "Known Limitations" (claimed no binary protocol / async /
  LISTEN-NOTIFY / COPY — all shipped) and the MQTT section (TLS-only +
  verify-on-by-default + exactly-once QoS 2 + `subscribe_many`) are now
  accurate. Dropped references to non-existent `spec/types.md` / `ir.md` /
  `bootstrapping.md`, fixed `CONTRIBUTING.md`'s `api/` → `nurlapi/`, a dead
  `HTTP_SERVER_PLAN.md` link in `ROADMAP.md`, the compiler's prefix-arity
  diagnostic (pointed at the moved README section → `docs/LIMITATIONS.md`),
  and `docs/GOTCHAS.md`'s cross-reference. All internal doc links verified.

### Added

- **MQTT: multi-topic SUBSCRIBE** (`mqtt_subscribe_many`) sends one
  SUBSCRIBE for N filters at a shared max QoS and validates every
  per-filter SUBACK reason code (a new `__mqtt_check_suback` that parses
  the property block instead of assuming a single trailing byte —
  `mqtt_subscribe_qos` now uses it too).
- **PostgreSQL advanced protocol features — binary, async, LISTEN/NOTIFY,
  COPY** (`stdlib/ext/postgres.nu`). Closes the last Tier-5 Postgres gap;
  all four are pure-NURL libpq FFI (no `runtime.c` bridge) and are
  exercised end to end by the new `examples/pg_advanced.nu`, live-verified
  against PostgreSQL 16.14.
  - *Binary result protocol*: `pg_exec_params_binary` requests
    `resultFormat = 1`; `pg_get_i16_bin` / `_i32_bin` / `_i64_bin` /
    `_bool_bin` / `_f64_bin` decode network-byte-order cells (`float8`
    reinterpreted from its IEEE-754 bit pattern, not a numeric cast), with
    `pg_get_length` / `pg_field_format` / `pg_binary_tuples`.
  - *Asynchronous queries*: `pg_send` / `pg_send_params` dispatch without
    blocking; `pg_get_result` (→ `?PgResult`, `None` when finished) and the
    blocking convenience `pg_await` collect results; `pg_consume_input` /
    `pg_is_busy` / `pg_socket` / `pg_flush` / `pg_set_nonblocking` hook into
    an event loop.
  - *LISTEN/NOTIFY*: `pg_listen`, `pg_notify_send`, `pg_notifies`
    (→ `?PgNotify { relname, be_pid, extra }`, read after
    `pg_consume_input`) and `pg_notify_free`.
  - *COPY*: `pg_copy_start` (accepts the `PGRES_COPY_IN` / `COPY_OUT`
    handshake that plain `pg_exec` rejects), `pg_put_copy_data` /
    `pg_put_copy_str` / `pg_put_copy_end` for `COPY … FROM STDIN`, and
    `pg_get_copy_data` (→ `?String`) for `COPY … TO STDOUT`.

### Fixed

- **Compiler: `??`-match on a result/option-typed *parameter* dropped its
  payload.** `@ f !S E r → S { ?? r { T x → ^ x } }` emitted `ret i64`
  against the `%S` return type (an LLVM "value doesn't match function
  result type" error), and the same gap mishandled a `( Vec u )` handle
  payload and dropped the unsigned flag on a `?u` parameter (sign-extending
  a byte ≥ `0x80`). `gen_fn_param` now records the
  `<param>__res_nurl_T` / `__res_t_llvm` / `__res_e_llvm` / `__opt_nurl_T`
  metadata that `gen_let_or_struct` already records for let-bound result
  vars, so `gen_match` reconstructs struct / pointer / unsigned payloads
  for a parameter scrutinee exactly as it does for a let binding. Bootstrap
  fixed point held; regression `compiler/tests/match_param_payload.nu`.
- **Compiler: an empty block `{}` returned from a void function emitted
  invalid IR.** An empty block is the unit/void value, but `gen_block` left
  the "last type" at whatever preceded it (i64 by default, i1 inside a
  conditional), so `^ {}` in a void function produced `ret i64 undef` —
  rejected by LLVM. The block now types as `void` when it has no trailing
  statement.
- **Compiler: undefined identifier in value position no longer emits an
  undefined SSA value with exit status 0** (PR #25 / `Fixes`). `gen_ident`'s
  bare `%<name>` fallback fired for *any* name lacking a `__ptr` / `__global`
  binding — so `: i x ^ a b c` emitted `ret i64 %a` that nurlc accepted and
  only clang rejected. The fallback now requires a by-value parameter and
  otherwise dies with "use of undefined identifier". This was critic.md §4's
  headline contradiction of "every trap is a compiler diagnostic".
  Regression `compiler/tests/should_fail_undef_ident.nu`.
- **Compiler: a within-statement prefix-arity cascade that swallowed the
  next `^` silently returned early** (PR #25 / `Fixes`). `: i x + 1` /
  `^ a` parsed as `+ 1 (^ a)` → `ret %a` plus a dead `add`, exiting 0. A new
  `g_ret_forbidden` flag (armed by a `gen_operand` wrapper around every
  value-operand parse, reset by `gen_stmt` and the `?` / `??` arm bodies)
  makes `gen_ret` refuse to emit a `ret` in operand position. Regression
  `compiler/tests/should_fail_cascade_caret.nu`.
- **Compiler: `??`-match on a direct-call scrutinee dropped pointer/handle
  payloads and option signedness** (PR #25 / `Fixes`). `: ( Vec u ) x ?? ( f
  … ) { … }` / `: s x ?? ( f … ) { … }` left the binding `undef` (no T-arm
  reconstruction, no result phi) for handle/pointer payloads, and `?? (
  vec_get [u] … ) { T b → # i b }` sign-extended an unsigned byte. The
  callee's Ok/Err-payload LLVM types and option-inner token are now recorded
  per function and surfaced to `gen_match`'s direct-call synthesis (with a
  bare-`i8*` inttoptr path for both arms). Regressions
  `compiler/tests/match_bind_call_handle.nu`, `match_call_opt_unsigned.nu`.
- **Compiler: option/result construction from a sized-int literal didn't
  truncate** (PR #25 / `Fixes`). `@ ?u { T 0x86 }` emitted `insertvalue {
  i1, i8 } …, i64 134, 1`, which clang rejected. `gen_agg_lit`'s opt/res
  payload coercion now truncs/sexts/zexts the literal to the payload width
  (option = T's real width, result = i64). Regression
  `compiler/tests/opt_lit_payload_width.nu`.
- **MQTT inbound QoS 2 is now exactly-once.** A retransmitted (DUP)
  QoS 2 PUBLISH was acknowledged but re-delivered to the application. The
  client now tracks inbound packet ids across their PUBREC…PUBCOMP window
  (`MqttClient.qos2_rx`, bounded, oldest evicted past 256), acknowledges a
  duplicate but delivers it only once. `__mqtt_parse_publish` returns
  `?MqttMessage` (None on a de-duplicated retransmit) and the dedup policy
  is unit-tested in `compiler/tests/mqtt_qos2_dedup.nu`. The doc-drift
  comment on `__mqtt_do_publish` (claimed a fixed packet id) was corrected.

### Security

- **MQTT TLS certificate verification is now configurable and on by
  default.** `mqtt_connect_cfg` / `mqtt_reconnect` previously hard-coded
  `verify = F`, so every TLS connection was effectively `--insecure`
  (MITM-able). `MqttConfig` gained a `tls_verify` field, threaded through to
  `tcp_connect_tls`; `mqtt_config` defaults it to T (peer-cert chain + host
  name verified against the system trust store). Set it F only for a
  self-signed broker in a trusted environment.
- **`pg_listen` SQL injection (critical) — fixed.** A channel name is a SQL
  *identifier* and cannot be a bound parameter, so it now goes through
  `pg_escape_identifier` (PQescapeIdentifier) before interpolation; raw
  concatenation previously let `pg_listen c "x; DROP TABLE …; --"` execute
  the injected statement. (`pg_notify_send` was already safe — it binds the
  channel as a value to `pg_notify($1, $2)`.)
- **Out-of-bounds read in the binary accessors (medium) — fixed.** A new
  `PQgetlength`-checked `__pg_bin_ptr` guards every `pg_get_*_bin`:
  reading an `int4` cell with the 8-byte `pg_get_i64_bin`, or any accessor
  on a binary SQL `NULL` (0 bytes), now returns `0` instead of reading past
  the cell into adjacent libpq buffer memory.
- **TLS is not verified by default — documented.** `pg_connect` and the
  file header now carry a prominent warning that libpq's default
  `sslmode=prefer` neither prevents a silent plaintext fallback nor
  verifies the server certificate (MITM-able), recommending
  `sslmode=verify-full sslrootcert=…` for non-local connections. Not
  force-defaulted, as that would break legitimate unix-socket / trusted-LAN
  connections. Minor: `pg_get_bool` gained a NULL-pointer guard, and the
  empty-on-NULL behaviour of `pg_escape_literal` / `pg_escape_identifier`
  is now documented.

## [0.9.3] — 2026-05-31

### Summary

A full **Game Boy (DMG) emulator written in NURL** now plays commercial
games with sound. `examples/gameboy/` passes Blargg `cpu_instrs` 11/11,
`instr_timing` and `02-interrupts`, is 100 %/pixel-perfect on dmg-acid2,
and runs *Tobu Tobu Girl* end to end — full gameplay plus a complete
4-channel APU mixed to stereo — in the browser at `/gameboydemo` via the
WebAssembly target. Building it drove three new language/compiler
features (**hex/binary integer literals**, pointer/aggregate global
initialisers, hex literals in `match`) and turned one
silently-accepted bare-literal statement into a hard compile error.

**Generics now range over option and pointer element types** — `Vec ?T`,
`vec_get [?T] → ??T`, `??T` parameters/returns and nested `??` matching
all compile (five front-end root-cause fixes). The PostgreSQL client is
**production-grade** (`stdlib/ext/postgres.nu` + `examples/psql.nu`),
including option-typed nullable params and getters
(`pg_exec_params_opt`, `pg_get_opt`), verified live against
PostgreSQL 16 under AddressSanitizer.

HTTP/2 + HPACK + WebSocket conformance suites remain green: h2spec 2.6.0
reports 146/146 cases against `examples/h2c_server.nu`; the
autobahn-testsuite fuzzing client reports 294 OK / 4 NON-STRICT /
3 INFORMATIONAL / 0 FAILED across all 301 RFC 6455 cases against
`examples/ws_echo.nu`. Both binaries run under ASan + UBSan
without findings.

Bootstrap fixed point at 1 772 342 B (stage1 ≡ stage2 byte-identical
IR).

### Added

- **Game Boy (DMG) emulator — `examples/gameboy/`.** A cycle-aware Sharp
  LR35902 core (every opcode + CB-prefix, exact Z/N/H/C flags + DAA,
  EI/DI IME enable-delay, HALT + HALT-bug, DIV/TIMA timer, interrupt
  dispatch) passing **Blargg `cpu_instrs` 11/11, `instr_timing` and
  `02-interrupts`**; a BG/window/sprite PPU that is **100 %/pixel-perfect
  on dmg-acid2** (0/23040 diff — LYC raster + window internal line
  counter); MBC1/3/5 mappers, joypad and OAM DMA; and a complete
  **4-channel APU** (2 square w/ sweep, 4-bit wave RAM, 15-bit-LFSR
  noise, 512 Hz frame sequencer, NR50/51 mix, DMG high-pass) mixed to
  stereo. The engine is split into a shared `core.nu` with `gb.nu` (CLI)
  and `gb_wasm*.nu` (wasm32-wasi → canvas) front-ends; the browser demo
  at **`/gameboydemo`** auto-starts *Tobu Tobu Girl* and plays it with
  sound through the playground audio shim. Two sub-instruction timing
  fixes (TIMA increments on the DIV falling edge; the fetch M-cycle is
  clocked before the instruction body) took it from a title-screen crash
  to full gameplay. Build the wasm at `-O2` (lower `-O` leaks the C
  shadow-stack pointer on the interrupt-dispatch path).
- **Generics over option / pointer element types.** Option (and pointer)
  element types are now first-class generic type arguments:
  `vec_get [?String] → ??String`, `Vec ?T` / `vec_push` / `vec_set` /
  `vec_free_with`, `??T` as a parameter and return type, and nested
  `?? o { T inner → ?? inner { … } }` matching all compile — every one of
  these previously failed at compile time. Five front-end root-cause
  fixes, each verified by a full bootstrap + test-suite run and an
  ASan-clean probe: (1) `parse_type_optopt` for the fused `??T` token;
  (2) `capture_type_arg_src` + `nurl_src_to_llvm` + an `opt_`
  mangle/demangle round-trip so compound type args like `[?String]` are
  one substitutable word; (3) `;`-separated closure parameter types so an
  aggregate type (`{ i1, %String }`) no longer truncates at its first
  space; (4) slice-vs-pointer store discrimination; (5) `int → aggregate`
  zeroinit. Test corpus on branch `feature/generic-option-types` (PR #21).
- **Hex / binary integer literals — `0xFF`, `0b1010`.** Added to the
  number lexer; the token carries the parsed value and keeps its spelling
  for diagnostics. Two companion compiler fixes: pointer- and
  aggregate-typed global initialisers (`: s g 0` → `global i8* null`,
  `: String g 0` → `zeroinitializer`, `inttoptr` for a nonzero address),
  and hex-literal normalisation in `match` (int-patterns `?? op { 0xCB →
  … }` and enum field-constraints `Code 0xFF → …` are rewritten to
  decimal before the `icmp`, since LLVM reads `0x…` as a hex float).
  Regression test `compiler/tests/hex_literals.nu`.
- **Production-grade PostgreSQL client + `psql` CLI.**
  `stdlib/ext/postgres.nu` reaches production grade: a `PgParams` builder
  (`pg_bind_text/str/int/bool/null`) for typed + NULL parameter binds the
  libpq/pgx way, `pg_prepare` / `pg_exec_prepared`, `pg_run`,
  `pg_begin/commit/rollback`, typed getters (`pg_get_int/f64/bool`),
  `pg_reset` / `pg_err_msg` / `pg_server_version` / `pg_escape_literal` /
  `pg_escape_identifier`, and — now that generics range over option types
  — option-typed nullable params/getters `pg_exec_params_opt
  ( Vec ?String )`, `pg_get_opt → ?String`, `pg_get_opt_int → ?i`. New
  `examples/psql.nu` (aligned-table renderer, command tags, multi-line
  `;` accumulation, `\dt \d \l \du \conninfo` meta-commands, `-c "SQL"`
  one-shot) and `examples/pg_optional.nu`. Verified live against
  PostgreSQL 16 under ASan (PRs #20 / #22).
- **Audio output in the WASM playground.** An `env.audio_out_push` host
  shim streams packed-stereo `i64` samples to 48 kHz Web Audio, letting
  WASM programs emit sound; demonstrated by `examples/audio_tone.nu` and
  used by the Game Boy demo's APU output.
- **Trait bounds on generic functions — `[A: Trait]`.** A generic type
  parameter may now carry one or more trait bounds: `@ my_max [A: Ord] A
  x A y → A { … }`. Trait-method dispatch inside a generic body already
  resolved to the concrete `impl` through monomorphisation (dispatch is
  keyed on the first argument's LLVM type, which becomes concrete at
  instantiation); the bound adds the up-front guarantee. `scan_impl_decl`
  now registers each `% Trait Type {}` as `Trait##<llvm>` in
  `g_trait_syms`; `gen_generic_fn_store` records per-tparam bounds; and
  `check_generic_bounds` (called from `gen_call` at every generic call
  site) verifies each bounded tparam's concrete type has the impl —
  turning a missing impl from a cryptic unresolved-call link error into a
  clear "type 'X' does not implement trait 'Y' required by bound A: Y"
  diagnostic. Generic detection in `gen_fn_decl` extended to recognise a
  colon anywhere in the `[…]` (a slice param's type never contains one).
  This removes the need to pass `Ord`/`Hash`/`eq` closures into generic
  helpers when an `impl` exists. Tests `compiler/tests/trait_bounds.nu`
  (positive, i + String) and `should_fail_trait_bound.nu` (bound
  violation → COMPILE FAIL). Bootstrap fixed point holds (stage1 ≡ stage2
  byte-identical at 1 730 148 B).
- **`??` match guards + or-patterns.** Two additions to `gen_match`:
  - **Guards** — `Pattern payloads ? <cond> → body`. The guard is
    evaluated *after* payload binding (so it can read the bound
    payloads); a false guard falls through to the next arm. Implemented
    by recording the guard's source span during arm parse and replaying
    it via `nurl_lex_set_pos` at the arm body, branching to the body or
    the next arm. A guarded arm does NOT satisfy exhaustiveness for its
    variant — a catch-all (unguarded or `_`) is still required. Not
    allowed on a `_` wildcard arm or combined with an or-pattern.
  - **Or-patterns** — `A | B | C → body`: several tag-only named
    variants share one body (`emit_or_chain` lowers the alternatives to
    a tag-compare chain). No payload binding or literal constraints; all
    listed variants count toward exhaustiveness.

  Test `compiler/tests/match_guards_or.nu`. Bootstrap fixed point holds
  (stage1 ≡ stage2 byte-identical at 1 720 428 B).
- **Compile-time const folding for integer globals.** A top-level
  integer const (`: i NAME …`, or u / sized ints — not `b`) may now take
  a prefix expression over integer literals instead of a single literal:
  `+ - * / << >> & | ^^` (not `%`, which collides with the trait/impl
  decl sigil at scan time). `const_eval_int` in `gen_const_decl` folds it
  to one value. Fixes the long-standing wart where e.g. the
  two's-complement minimum needed a niladic helper — `stdlib/std/int.nu`
  now exposes `: i INT_MIN - -9223372036854775807 1` directly
  (`int_min_val` retained, delegating to it). Transparent (computes a
  value, hides no control flow); fits the parse-directed architecture.
  Test `compiler/tests/const_eval.nu`. Bootstrap fixed point holds.
- **`select` over channels — `?? { … }`** — Go-style select. A `??`
  whose scrutinee is immediately `{` (no value to match) is a channel
  select; each arm `[T] ch → bind { body }` receives from one channel
  and the construct proceeds with the first ready arm. With no `_`
  default it BLOCKS until some channel is ready (value sent or channel
  closed); a `_ → { … }` default makes it non-blocking. `bind` is the
  `?T` the receive yields (None ⇒ closed). Arms are heterogeneous (each
  channel may carry a different element type) and tried in source order.
  Implemented in `gen_select` (compiler/nurlc.nu) as a desugaring that
  synthesises NURL source from the verbatim user channel-exprs + bodies
  and compiles it through a sub-lexer — no raw IR, no new lexer token.
  The blocking rendezvous (a shared `SelectWaiter` armed on every
  channel, fired by senders/closers under the channel mutex) lives in
  `stdlib/std/channel.nu` via the type-erased `chan_raw_poll` /
  `chan_raw_arm` / `chan_raw_disarm` / `select_waiter_*` helpers — the
  element type drops out of the orchestration, so one non-generic code
  path serves channels of any type. Test
  `compiler/tests/select_basic.nu` (deterministic default / value /
  closed / priority cases always-on; concurrent blocking path gated on
  `NURL_NET_TESTS=1`). Bootstrap fixed point holds (stage1 ≡ stage2
  byte-identical at 1 691 603 B).
- **Stdlib numeric + text utility round-out** — four pure-NURL
  additions (no compiler changes, each with an offline test):
  - `stdlib/std/int.nu`: `int_gcd`, `int_lcm`, `int_isqrt` (Newton-method
    exact floor sqrt). Test `compiler/tests/int_extra.nu`.
  - `stdlib/std/float.nu`: `float_trunc`, `float_cbrt`, `float_hypot`,
    `float_log2`, `float_log10` (direct libm FFI) + pure-NURL
    `float_sign`. Test `compiler/tests/float_extra.nu`.
  - `stdlib/core/string.nu`: `string_join` (complement of `string_split`)
    and `string_count` (non-overlapping occurrence count). Test
    `compiler/tests/string_join_count.nu`.
  - `stdlib/core/char.nu`: `is_upper`, `is_lower`, `is_hexdigit`,
    `to_upper_ascii`, `to_lower_ascii`, `hex_val`. Predicates use the
    same `# i <bool-expr>` shape as the existing `is_alpha` / `is_digit`
    family — now returning a canonical 1/0 thanks to the cast fix below.
    Test `compiler/tests/char_extra.nu`.

### Fixed

- **Pointer-vs-integer comparison emitted invalid IR.** `gen_binary`
  produced `icmp eq i8* %p, 0`; comparison operators now `ptrtoint` any
  pointer operand to `i64` and compare in `i64`, so `== raw 0`
  null-checks compile. Found bringing `postgres.nu` to production grade.
- **`^ <void-call>` (returning a `→ v` call) emitted a value return.**
  Returning the result of a void function now lowers to `ret void`
  instead of attempting to return a non-existent value. Found in the
  postgres work.
- **A bare numeric/string literal as a statement is now a hard compile
  error.** Previously `& m 255 0x40` (single `&`) silently discarded the
  trailing `0x40` — a bare-literal discard statement the compiler
  accepted — which masked a real masking bug in the Game Boy PPU's
  STAT-bit-6 handling. `gen_block_stmts` / `gen_block_ret` now reject a
  bare literal whose value is unused. (The no-workarounds dividend from
  debugging dmg-acid2.)
- **`# i <bool>` now zero-extends (was -1 for true).** Casting a boolean
  (an `i1` from a comparison / `&` / `|` / `!`) to a wider integer
  emitted `sext i1`, so `# i true` was -1 instead of 1. Harmless for the
  ubiquitous `!= 0` callers, but it silently broke every predicate
  documented as "→ 1": `is_alpha` / `is_digit` / `is_space` /
  `is_alnum_us` all returned -1 for true. NURL has no signed 1-bit type,
  so a boolean true is canonically 1 — `gen_cast` now forces `zext` for
  any `i1` source (comparisons never set the `__last_unsigned__`
  side-channel that the unsigned-widen path relies on, hence the explicit
  guard). Latent fix across the whole stdlib; no existing test output
  changed (nothing depended on the -1). Regression
  `compiler/tests/cast_bool_int.nu`. Bootstrap fixed point holds
  (stage1 ≡ stage2 byte-identical at 1 660 838 B).
- **`HttpOptions` struct (HTTP client)** — `stdlib/ext/http.nu` gained
  `HttpOptions { i timeout_ms, i connect_timeout_ms, i follow_redirects,
  i max_redirects, i verify_tls, s user_agent }` bundling the per-request
  transport overrides that were previously hardcoded in the libcurl
  orchestrator. New entry points: `http_options_default → HttpOptions`,
  `http_request_with_opts`, and `http_get_opts` / `http_post_opts`
  conveniences. The orchestrator body moved into
  `__libcurl_perform_full_opts` (wires `CURLOPT_FOLLOWLOCATION` /
  `MAXREDIRS` / `SSL_VERIFYPEER` / `SSL_VERIFYHOST` / `USERAGENT` from the
  struct); the legacy timeout-only `__libcurl_perform_full_to` is now a
  thin shim over it, so `http_request` / `http_request_to` are
  behaviour-preserving. `user_agent` is borrowed `s` so HttpOptions owns
  nothing (no free fn, safe by-value). WinHTTP / stub backends honour
  only the two timeouts (redirect / TLS / UA ignored — documented).
  Stdlib-only; compiler IR unperturbed. Tests: offline
  `compiler/tests/http_options.nu` (always-on) + a live `GET_OPTS` case
  in `compiler/tests/http_basic.nu`.
- **`examples/h2c_server.nu`** — minimal cleartext-HTTP/2 ("h2c,
  prior-knowledge") echo server (~135 LOC). Async accept loop via
  `stdlib/std/async.nu` so h2spec's probe + test connections can be
  served concurrently; per-conn read timeout of 1 s keeps the
  sequential accept queue draining when a test deliberately leaves
  a connection half-open; response body sized ≥ 5 bytes so the
  `dataLen >= 5` gate in h2spec §6.9.2/2 runs the test instead of
  skipping. Verified green under both `./nurl.sh` and
  `NURL_SAN=1 ./nurl.sh`.
- **`examples/ws_echo.nu`** — minimal WebSocket echo server (~110
  LOC). Uses the stdlib `ws_perform_handshake` + `ws_serve_messages`
  pair against the same TCP accept loop. Per-server `WsLimits`
  raises `fragment_max_count` to 131 072 so autobahn §9.x's 4-MiB
  message split into 65 536 frames assembles successfully; per-
  frame and per-message byte caps stay at the stdlib defaults.
- **`NURL_SAN=1` support in `nurl.sh`** — drops `-flto`, adds
  `-fsanitize=address,undefined -fsanitize-address-use-after-scope
   -fno-omit-frame-pointer -fno-sanitize-recover=all` at the link,
  and builds a side-by-side `stdlib/runtime_san.o` (non-LTO,
  matching flags) if `stdlib/runtime.c` is newer than the cached
  artefact. Matches the toolchain `./build.sh --san` already uses
  for its own corpus.
- **HPACK lowercase-header-name encoder** (`stdlib/ext/http2_hpack.nu`
  `__hpack_lower_name_dup`) — RFC 9113 §8.2.2 mandates lowercase
  header field names on the wire; `hpack_encode_headers` now
  lowercases every name before encoding. Previously curl's HTTP/2
  parser rejected our `Content-Type` response header.
- **Inline WINDOW_UPDATE pump in `__h2_send_response`** — when the
  stream OR connection send-window is exhausted mid-response, the
  writer reads frames off the peer and applies WINDOW_UPDATE /
  SETTINGS / PRIORITY semantics in place (RFC 9113 §5.2.1, §6.9.1).
  HEADERS for a new stream during the pump is refused with
  RST_STREAM(REFUSED_STREAM) per §5.1.2. Empty `DATA(END_STREAM)`
  fallback (§6.9.1 permits zero-length DATA + END_STREAM regardless
  of window state) closes the stream cleanly when the pump bails.
- **HTTP/2 request HEADERS validation pass** (`__h2_validate_request_
  headers` in `stdlib/ext/http2_conn.nu`) — RFC 9113 §8.3 / §8.2.1 /
  §8.2.2: lowercase names, pseudo-headers precede regular ones,
  exactly one `:method` / `:scheme` / `:path` (non-empty), no
  duplicate or response-only or unknown pseudo-headers, no
  connection-specific headers (`Connection`, `Proxy-Connection`,
  `Keep-Alive`, `Transfer-Encoding`), and `TE` — if present — holds
  exactly `"trailers"`. Runs immediately after HPACK decode succeeds
  on both the HEADERS+END_HEADERS and HEADERS+CONTINUATION+
  END_HEADERS paths.
- **HTTP/2 frame-validation pass** — SETTINGS / GOAWAY / RST_STREAM
  / PRIORITY / DATA stream-ID + length + ACK rules per §6.5 / §6.4
  / §6.3 / §6.1 / §6.8.
- **HEADERS-on-existing-open-stream = trailers** (§8.1) — accepting
  a HEADERS frame on a stream already in `open` / `half-closed-
  local` state as the trailers section. Trailers MUST carry
  END_STREAM; decoded fields are discarded but `end_stream_received`
  is marked and the handler is dispatched.
- **PUSH_PROMISE rejection** (§6.6) — client→server PUSH_PROMISE is
  now PROTOCOL_ERROR (we advertise SETTINGS_ENABLE_PUSH=0).
- **§5.3.1 self-dependency check** for PRIORITY and HEADERS-with-
  PRIORITY-flag — a stream MUST NOT depend on itself; rejected as
  PROTOCOL_ERROR.
- **§6.9.1 flow-control overflow detection** — WINDOW_UPDATE that
  carries a stream's or connection's send-window above 2^31-1 is
  now FLOW_CONTROL_ERROR (stream-level → RST_STREAM, conn-level →
  GOAWAY).
- **§5.1 idle-stream WINDOW_UPDATE** — WINDOW_UPDATE on a stream
  with sid > last_peer_stream_id (never opened) is PROTOCOL_ERROR;
  on a closed stream silently no-ops.
- **HPACK §4.2 dynamic-table-size-update placement check** — size
  updates after any indexed/literal field in the block are
  COMPRESSION_ERROR (new `seen_field` flag in `hpack_decode_block`),
  and the new size is bounded by `h2_default_header_table_size`
  (4 096) — our advertised SETTINGS_HEADER_TABLE_SIZE — rather than
  the table's current `max_size`, which may have been lowered by a
  previous update in the same connection.
- **§8.1.1 content-length consistency check** (`__h2_content_length
  _mismatch`) — when a request carries `content-length`, the sum of
  DATA-payload lengths MUST equal that value. Mismatched (or
  unparseable, or duplicated and disagreeing) content-length becomes
  PROTOCOL_ERROR before handler dispatch.
- **RFC 6455 §5.5.1 / §7.4.2 WebSocket close-frame validation** —
  payload length 1 → `WsInvalidCloseCode` (close code 1002, not
  1000); status code outside 1000–2999 OR 1004 / 1005 / 1006 /
  1015 / 1016+ → close 1002; close-reason bytes validated as UTF-8.
  Previously a close frame's payload was discarded outright and the
  server replied with `WsClosedByPeer` → 1000 regardless of what the
  peer sent.
- **TCP_NODELAY on accepted sockets** (`stdlib/runtime.c`,
  `nurl_tcp_accept`) — disables Nagle's algorithm on every accepted
  TCP connection. Small framing-level ACKs (SETTINGS-ACK, PING-ACK,
  WINDOW_UPDATE) were otherwise pinned behind the previous write
  for up to 40 ms, which is exactly the window h2spec's per-test
  short timeouts can't tolerate.
- **`h2_default_header_table_size` constant** in
  `stdlib/ext/http2_frame.nu` — value `4 096`, used as the upper
  bound for HPACK dynamic-table-size updates and matches the
  RFC 9113 §6.5.2 default for SETTINGS_HEADER_TABLE_SIZE.

### Changed

- **`scan_fn_sigs` is now brace-depth-tracked** — only TT_AT / TT_AMP
  / TT_DOLLAR / TT_PERCENT openers at depth 0 trigger their
  respective dispatch branches; everything inside `{ ... }` advances
  silently. Matches the pattern `scan_type_names` already used (see
  the docstring there). Closes the family of param-walk-desync bugs.
- **HTTP/2 GOAWAY-receive no longer triggers immediate shutdown** —
  per RFC 9113 §6.8 the receiver of GOAWAY MUST keep processing in-
  flight frames (PING, RST_STREAM, in-progress streams) until the
  peer closes the socket; only NEW stream creation is forbidden.
  Previously we hard-exited the serve loop on the first GOAWAY,
  which broke the h2spec GOAWAY-then-PING sequence.
- **HTTP/2 invalid-preface error path** sends GOAWAY only when the
  preface was structurally invalid (`H2FrameBadPreface`); on a read
  error (timeout / EOF / IO) we tear down silently. GOAWAY-on-
  every-preface-error was being seen by h2spec's per-test probe
  connections and counted as the test response.

### Fixed

- **`scan_fn_sigs` brace-depth desync** — the `@` inside a closure-
  shaped struct field type (`( @ HttpResponse HttpRequest ) handler`)
  was treated as the start of a function declaration; the param
  walker then read `HttpResponse` as the phantom `fname` and the
  NEXT type-name-shaped token (in `stdlib/ext/http_server.nu`,
  `DosLimits`, declared 5 lines later) as that phantom function's
  `ret_ty`, silently writing `syms["HttpResponse"] = "%DosLimits"`.
  `gen_match`'s wide-payload reconstruction for a
  `: ! HttpResponse WsErr rr (...)` binding then looked up
  `syms["HttpResponse"]` to size the heap-box load and emitted
  `inttoptr i64 ... to %DosLimits*` + `load %DosLimits` + `bitcast
   %DosLimits* ... to i8*` against the real HttpResponse pointer.
  Under -O1+ this manifested as a runtime nurl_peek of a misaligned
  sub-page address (the HttpResponse i64 status field read as a Vec
  ctl). Under -O0 the extra reload of the alloca round-tripped the
  bits exactly so the struct's field accesses happened to land at
  the right offsets, hiding the bug.
- **`__h2_stream_to_request` double-freed `req.query`** when the
  request had no `?` in the path — the field was freed
  unconditionally but only reassigned inside the `qi >= 0` branch.
  `request_free` then freed the dangling pointer again. Clear ASan
  use-after-free on the very first h2c request through h2spec.
- **`__h2_decode_stream_headers` freed the old `cur.dec_dyn` before
  assigning the new `dd.dyn`** — but `HpackDynTable.entries` is
  aliased through the by-value pass into `hpack_decode_block`, so
  the two wrappers shared one Vec ctl. The free turned the new
  assignment into a dangling pointer; subsequent reads on
  connection close tripped nurl_peek.
- **`hpack_decode_block` failure path freed `cur`** — but `cur` was
  initialised from the input `dyn` (struct copy, entries Vec
  pointer-aliased), so freeing in the error path left the caller's
  `dec_dyn` pointing at a freed Vec entries pointer. The next
  h2_conn_free vec_free_with double-freed.
- **`__h2_frame_err_to_conn` returned bare enum tags from `??`-arm
  bodies** when the function return type wrapped them as a struct;
  follow the established `__net_err_of` convention with explicit
  `# H2ConnErr Tag` casts so the IR's `ret %H2ConnErr` matches the
  function signature.
- **`nurl_str_slice_unsafe` did pointer-load instead of pointer
  arithmetic** — `. rp from` lowers to "load the byte at rp+from",
  not "compute address rp+from". The code intended an unsafe
  substring view (rp + from interpreted as a string pointer); now
  spelled `# s + # i raw from` (cast-add-cast).
- **Two latent parenthesised-operator compile errors** in
  `stdlib/ext/http2_conn.nu` — `( % n 6 )` and `( . rp from )`. The
  diagnostic that rejects these landed 2026-05-22 but
  `http2_conn.nu` was never on the build/test path, so they sat
  silently until `examples/h2c_server.nu` pulled the file in.
- **`__pow2` defined in two translation units** — once in
  `stdlib/ext/http_response.nu` (used for hex-format expansion) and
  once in `stdlib/ext/http2_hpack.nu` (used for HPACK integer
  width). Linker rejected the redefinition the first time both
  modules were used together; the HPACK helper is now
  `__hpack_pow2`.
- **`__h2_apply_settings` sign-extension** — byte-shift-and-OR
  assembly of the 24-bit length / 32-bit value fields used `# i u`
  to widen each payload byte without masking, so any byte ≥ 0x80
  propagated as a negative i64 into the next shift, corrupting
  `value`. Fixed with explicit `& 255` masks at every byte read; the
  same fix applied to the WINDOW_UPDATE increment decode in the
  main serve loop and in `__h2_pump_one_frame`.
- **`autobahn-testsuite §6.4.1-4` UTF-8 fail-fast** — accepted as
  NON-STRICT (the spec permits either streaming UTF-8 rejection or
  whole-message validation; we do the latter). Documented for
  follow-up work.

### Tooling / dev experience

- **`./build.sh --san` ASan/UBSan corpus runs WebSocket close
  validation** end-to-end through autobahn-testsuite's first seven
  case sections (92/92 OK; 0 sanitizer findings).
- **`docs/GOTCHAS.md` remains empty** — every gotcha surfaced
  during the interop push (parenthesised-operator calls, sign-
  extension, `__pow2` collision, enum-tag-cast-on-return) is
  diagnosed by the compiler at compile time.
- **`.github/workflows/bench.yml`** — reproducible CI bench runner.
  Triggers on push-to-main (paths-filtered to bench/, compiler/,
  stdlib/, bench.yml itself), `workflow_dispatch`, and a weekly
  Monday 06:00 UTC cron. Installs clang + rustup stable + the FFI
  libs the regular `ci.yml` uses, bootstraps nurlc, runs
  `bench/run.sh 5` on a fixed `ubuntu-latest` 2-vCPU runner, and
  uploads the results as a workflow artifact. Manual / scheduled
  runs additionally commit a refreshed `bench/RESULTS_CI.md` back
  to main. The README's headline numbers (captured on a 12-core Intel
  @ 3.5 GHz) stay in `RESULTS.md` as the hand-captured figures;
  `RESULTS_CI.md` is the reproducible baseline.

### Tokeniser-aware token-efficiency baseline

- **`bench/token_efficiency.py` + `bench/TOKEN_EFFICIENCY.md`** —
  BPE-aware token counts using `tiktoken`'s `cl100k_base`
  (GPT-3.5 / GPT-4 / Claude legacy), `o200k_base` (GPT-4o /
  o-series), and `gpt2` (proxy for Llama-3, which is HF-gated)
  against every cross-language benchmark in `bench/`. NURL/Python
  BPE-aware token-count ratios on these three benchmarks are
  0.82–0.95× (LCG, all encoders) / 1.88–2.06× (sieve) /
  1.60–1.77× (json_parse).
- **`bench/{lcg,sieve,json_parse}.nu` cleanup** — dropped the
  redundant `$ "stdlib/core/io.nu"` import (the `puts` and
  `nurl_str_int` calls resolve through the compiler's libc/runtime
  prelude) and switched the trailing print from
  `( puts ( nurl_str_int x ) )` to the one-call
  `( nurl_print_int x )`. `sieve.nu` also drops the redundant FFI
  decls for `malloc` and `free` (both pre-registered by
  `init_syms`). Net result: −29 to −80 source bytes per file, NURL
  token counts down ~6–10 % across every encoder, and `@main` LLVM
  IR is byte-identical for both compute benchmarks.

### Borrow checker

- **`--strict-borrowck` (off by default)** — opt-in mode that
  extends two existing on-by-default checks:
    - **Aliased mutation through `. obj field` arguments.** The
      default N-readers-XOR-1-writer check fires only when both
      aliasing arguments at a call site are bare identifiers.
      Strict mode also recognises `. obj field` as an access of the
      root binding `obj`, so `( swap c . c n )` is now flagged when
      one of the arguments is `inout`. The iterator-invalidation
      check is widened in the same shape.
    - **`# *T <owned-binding>` raw-pointer escape.** When a `*T`
      cast's source binding sits on any of the auto-drop
      side-tables (`__owned_strings__` / `__owned_slices__` /
      `__owned_struct_fields__`) OR is a non-parameter heap binding
      (%Struct / enum / aggregate, mirroring the move-tracker's
      `bck_let_alias` heuristic), strict mode flags the cast: the
      binding's auto-drop at scope exit invalidates the pointer.
- Regression tests `compiler/tests/borrow_strict_field_alias.nu`
  and `compiler/tests/borrow_strict_raw_ptr_escape.nu` — both
  compile cleanly under the default checker and error out under
  `--strict-borrowck`. `compiler/tests/run_tests.sh` recognises any
  `borrow_strict_*` filename and adds the flag automatically.
- Bootstrap fixed point unchanged: strict mode is purely a
  diagnostic-only analysis pass.



## [0.9.2] — 2026-05-28

### Summary

`play.nurl-lang.org` no longer runs Python at runtime. `nurlapi/` is
a 3 000+-LOC NURL HTTP server with a full Model Context Protocol
server over `/mcp` (15 tools, 7 resources, 1 prompt), serving five
cross-compile build targets (native ELF, wasm32-wasi, mingw-w64
PE32+, macOS Intel, macOS Apple Silicon + the rest of the
`/build_target` registry). One static NURL binary is PID 1 inside
the runtime image.

A `nurl_poke` / `nurl_peek` byte-vs-slot index overrun in
`server_run_pool` (and three other call sites) that scribbled 7×N
bytes past a worker-handles buffer is fixed. The overrun had
manifested as random route / closure corruption under thread load.

Full test corpus + sanitiser corpus (ASan + UBSan + LSan, 281 tests)
green. Bootstrap fixed point at 1 620 300 B (stage1 ≡ stage2
byte-identical IR).

### Added — pure-NURL playground server (`nurlapi/`)

Replaces the Python FastAPI playground end-to-end. One static NURL
binary as PID 1; the runtime image is a slim Debian-bookworm stage
that only needs clang-16 + the cross-compile toolchains baked in.

**Route surface** (POST unless noted):

- `/build` → native Linux x86_64 ELF
- `/build_wasm` → wasm32-wasi (uses `prepare_ir_for_wasi` IR shim;
  wasm32 ABI rename + libc shims for `malloc` / `puts` / `write` etc.)
- `/build_windows` → mingw-w64 PE32+ via two-stage `clang -c` then
  `x86_64-w64-mingw32-gcc` link (static libcurl chain when the
  `runtime.win.curl` marker is present)
- `/build_macos` → Mach-O via zig cc
- `/build_target` → multi-target dispatch (linux-x64-musl,
  linux-arm64-musl/-gnu, linux-riscv64-musl, macos-x64, macos-arm64,
  windows-x64) over a single shared `_build_zig_cross` helper
- `GET /examples`, `GET /examples/*name` — bundled example listing +
  individual source
- `GET /stdlib`, `GET /stdlib/*path` — recursive .nu listing (84
  entries) + per-file `{name, source, bytes}` JSON
- `GET /tests`, `GET /tests/*path` — same shape for the compiler
  test corpus (281 entries)
- `GET /targets` — target registry (the dropdown the UI builds from)
- `GET /readme` / `/readme.md`, `/roadmap` / `/roadmap.md`,
  `/gotchas` / `/gotchas.md`, `/grammar.ebnf` — doc passthroughs +
  HTML-rendered alternates (pure-NURL Markdown→HTML renderer:
  headings, fenced code, bold/em, code spans, links, autolinks,
  images, ul/ol, blockquote, hr; tables + nested lists deferred)
- `GET /LICENSE-MIT`, `/LICENSE-APACHE`, `/NOTICE`, `/license`,
  `/license/{mit,apache}` — license endpoints (raw + HTML-wrapped)
- `GET /openapi.json` — minimal but valid OpenAPI 3.1 doc enumerating
  every public route
- `GET /health` → toolchain status (60+ stdlib modules + per-tool
  liveness)
- `GET /mcp-info` → MCP server probe (tools / resources / prompts
  catalogue + a `client_config_example` built from the request's
  Host header or `NURL_PUBLIC_URL`)
- `GET /download/:id/:file` → built artifact download
- OAuth 2.0 / OIDC rubber-stamp stubs so Claude-Desktop-class MCP
  clients that probe `.well-known/*` succeed: `oauth-protected-
  resource` (+`/mcp`), `oauth-authorization-server`, `openid-
  configuration`, `POST /register`, `GET /authorize` (instant 302),
  `POST /token`
- Static UI at `/`, `/favicon.{ico,svg}`, `/static/*`, `/*path`

**Build response shape** mirrors `api/` (Python) exactly: combined
`stdout` / `stderr`, parsed `nurlc_errors[]` (`{file, line, col,
message}`), `ll_artifact` + `binary_artifact` with `{name, bytes,
download_url, token}`, `nurlc_returncode` / `clang_returncode`,
`uses_canvas` / `uses_audio`. New shared helpers:
`parse_nurlc_diagnostics`, `combine_stderr`, `make_artifact_json`,
`stamp_build_response`, `nurlc_failure_response`,
`push_native_runtime_libs`.

`nurlapi/Dockerfile` — two-stage Debian bookworm image. Stage 1
bootstraps nurlc, downloads WASI SDK 24 + Zig 0.13, builds a static
libcurl-mingw for the Windows target, pre-builds the six zig-target
runtime objects + warms the zig per-target libc cache so the first
`/build_target` per target is a fast cache hit rather than a cold
multi-second libc compile, compiles the nurlapi binary itself.
Stage 2 is a slim runtime image (clang-16 + cross-compile toolchains
only, no Python).

`nurlapi.sh` — bring-up wrapper. `./nurlapi.sh` builds + runs on
port 8000; `./nurlapi.sh bind` skips the Docker rebuild and bind-
mounts the freshly-built local binary + stdlib + examples + tests
+ root docs into the running container (inner dev loop: edit `.nu`
→ `./nurlapi.sh bind` → hit endpoint, ~30 s vs ~10 min). Flags:
`--no-cache` / `--port=N` / `--rm` / `--detach` / `--build-only` /
`--name=NAME` / `--help`.

`nurlapi/e2e_test.{py,sh}` — end-to-end test driver covering every
endpoint.

### Added — full MCP server over `/mcp`

`stdlib/ext/mcp_http.nu` + `nurlapi/main.nu`. Streamable HTTP
transport (POST /mcp), FastMCP handshake parity:

- `initialize` (protocolVersion `2025-03-26`, FastMCP capabilities
  shape, `instructions` blurb verbatim, serverInfo `nurl-playground
  0.9.2`)
- `ping`, `tools/list` (15 tools), `tools/call` (dispatch by name)
- `resources/list` (7 `nurl://` URIs), `resources/read`
- `prompts/list` (1 prompt: `nurl_coding_assistant`), `prompts/get`
- `notifications/*` (no reply, 202 Accepted)
- JSON-RPC 2.0 batches (top-level array → array reply,
  notifications dropped per spec)

**Tools (full Python parity):**

- Build (5) — `nurl_build_native`, `nurl_build_wasm`,
  `nurl_build_windows`, `nurl_build_macos`, `nurl_build_target`
  (enum-typed target id)
- Browse (3) — `nurl_list_examples`, `nurl_list_stdlib`,
  `nurl_list_tests`
- Read (7) — `nurl_read_example`, `nurl_read_stdlib`,
  `nurl_read_test`, `nurl_read_grammar`, `nurl_read_readme`,
  `nurl_read_roadmap`, `nurl_read_gotchas`

Build tools dispatch via loopback HTTP to the server's own `/build`
endpoints (`NURL_MCP_LOOPBACK_URL`, default `http://127.0.0.1:8000`):
zero duplication of the canonical handler logic.

**Reliability fixes vs Python reference:**

1. **Session persistence across container restarts.** Python
   validated `Mcp-Session-Id` against a per-process in-memory
   whitelist — fresh pod = fresh whitelist = previously-issued sids
   rejected. NURL approach: session ID is opaque to the server.
   First request (no sid) → server generates 16-hex-char sid, echoed
   in `Mcp-Session-Id` response header; subsequent requests with sid
   → echoed verbatim, no validation. Pod restart → client sid still
   accepted, no reconnect required.
2. **Burst handling.** Python's asyncio event loop serialised
   request handling. NURL piggybacks on `server_run_pool`'s
   16-pthread worker pool — every POST /mcp gets its own worker
   thread, no serialisation. Measured: 50 concurrent `tools/list`
   in 65 ms wall on a single host (~770 req/s peak).

**Streamable HTTP content-negotiation** in `stdlib/ext/mcp_http.nu`:
when the client sends `Accept: text/event-stream` (every official
SDK does), the JSON-RPC reply is wrapped as `event: message\r\ndata:
<json>\r\n\r\n` with `Content-Type: text/event-stream` +
`Cache-Control: no-cache`. Legacy clients without the Accept header
still get plain `application/json`.

### Added — `http_router` HEAD + OPTIONS

`router_handle` now answers HEAD and OPTIONS requests without each
handler having to know about them — same shape FastAPI / Express /
most modern HTTP frameworks ship by default.

- **HEAD** (RFC 7231 §4.3.2): treated as a GET for the purpose of
  route matching — falls through to the GET handler, then pins
  `Content-Length` to the GET body's would-have-been length and
  clears the body Vec so the wire-level serialisation emits headers
  + blank line + zero bytes.
- **OPTIONS** (RFC 7231 §4.3.7): the router answers directly, no
  handler involved. Walks every registered route, collects distinct
  methods whose pattern matches the request path, auto-adds HEAD
  (when GET is among them) and OPTIONS (always), returns 204 No
  Content with the assembled `Allow:` header. Root-level catch-alls
  (patterns starting with `/*`) are excluded from OPTIONS
  enumeration so they don't pollute the advertised method list.

Two new helpers: `__strip_body_for_head`, `__router_options`.

Verified live against nurlapi: `OPTIONS /health` → 204 `GET, HEAD,
OPTIONS`; `OPTIONS /build` → 204 `POST, OPTIONS`; `OPTIONS
/nonexistent` → 404 (catch-all filter working); `HEAD /health` →
200 `Content-Length: 1570`, body 0 bytes.

### Fixed — `nurl_poke` / `nurl_peek` byte-vs-slot heap overrun (critical)

`server_run_pool` in `stdlib/ext/http_server.nu` allocated an N×8-byte
buffer for N worker thread handles and then wrote into it with
`nurl_poke thandles (* j 8) traw` — passing a **byte offset** where
`nurl_poke` expects a **slot index**. `nurl_poke` scales by 8
internally, so each "write at byte offset j*8" actually landed at
byte offset j*64 — scribbling 7×N bytes past the buffer end.

The overrun survived for years because it consistently hit the
malloc arena's slack-padding zone, which on glibc was unallocated
"redzone-shaped" space between the worker-handles block and the
next live allocation. The behaviour only collapsed once enough other
heap traffic crowded the arena and a real load-bearing allocation
landed in the spillover window — at which point one of the routes,
or its `RouteImpl` pointer, or its closure environment, would get
clobbered and the next request through that route would crash.

This was previously misdiagnosed as a `Vec[Route]` multi-field-struct
stride hazard under pthread + clang -O2 (the boxed-handle pattern in
`stdlib/ext/http_router.nu` was added as a workaround for the
symptom). Route storage was always sound; routes just happened to
share the arena page that got smashed. The `http_router.nu` comment
block has been rewritten to credit the real cause.

ASan caught the real root cause when `nurlapi/main.nu` grew from 14
to 22 routes — the bigger router-build allocation budget shifted
what landed in the spillover. Same anti-pattern was present in three
other call sites, fixed atomically:

- `stdlib/ext/http_server.nu` `server_run_pool` (3 sites: 2 poke + 1 peek)
- `stdlib/ext/postgres.nu` `pg_exec_params` (2 sites)
- `compiler/tests/thread_basic.nu` (2 sites — masked by malloc slack)

Each: `(nurl_poke buf (* j 8) v)` → `(nurl_poke buf j v)`.

Regression test `compiler/tests/nurl_poke_slot_index.nu` allocates
an N×8 buffer (N=32, well past any malloc-slack forgiveness zone),
writes N distinct markers, reads them back, verifies bit-for-bit.
Under ASan in `run_san_tests.sh` it fails-fast as
`heap-buffer-overflow` on the first overrun if anyone reintroduces
the byte-as-slot mistake.

### Fixed — playground init no longer blocks on a CDN

`<script type="module">` in `api/static/index.html` and
`nurlapi/static/index.html` started with a top-level
`import { … } from "https://esm.sh/@bjorn3/browser_wasi_shim@0.3.0"`.
ES-module top-level imports are awaited before any statement in the
module body runs — if esm.sh is slow, blocked, or rejected by the
browser (ad-blocker, CSP, offline cache, transient DNS), the module
never reached its first statement, so `refreshHealth()`,
`loadExamples()` and `loadTargets()` never fired. The health pill
stayed "checking…", dropdowns stayed empty, and the page looked
like the server's `/health` was down even though the server was fine.

Fix: replace the static import with a lazy `import(WASI_SHIM_URL)`
inside a `loadWasiShim()` helper, called only from inside `run()` —
the one place that actually needs the shim. The module body now has
zero top-level awaitable imports and initialises synchronously. A
CDN failure surfaces in `run()`'s `logLine` path and aborts only
that one Run-click, not the whole page.

### Changed — `/build_windows` two-step compile (clang) + link (mingw-gcc)

Mirrors Python `api/`'s approach: `clang --target=x86_64-w64-mingw32`
is great at parsing IR but its mingw linker driver can't resolve
mingw-w64's installed support libraries (`-lgcc`, `-lwinpthread`,
`crtbeginS.o`, etc.). Single-step `clang ... runtime.win.o -o
out.exe` therefore fails with `/usr/bin/x86_64-w64-mingw32-ld:
cannot find -lgcc`. Two steps fix it:

1. `clang --target=x86_64-w64-mingw32 -c file.ll -o file.o` — clang
   compiles IR to a mingw-flavoured object.
2. `x86_64-w64-mingw32-gcc file.o runtime.win.o -lpthread …
   [optional libcurl] -o file.exe` — mingw's own gcc owns its
   libgcc / libwinpthread / CRT search paths and finishes the link
   cleanly.

The optional libcurl chain (`-L<curl-mingw>/lib -lcurl -lws2_32
-lcrypt32 -lbcrypt -lncrypt -lsecur32 -ladvapi32`) is added only
when the `stdlib/runtime.win.curl` marker is present — same gate
Python uses. Combined stderr now layers all three stages
(`nurlc` → `clang -c` → mingw-gcc link) so the playground's "BUILD
FAILED" panel surfaces whichever stage actually errored;
`final_rc` prefers the compile return code over the link return
code (a failing compile produces the more actionable diagnostic).

Five compile targets now produce real binaries end-to-end:

- `/build` → 78 KB Linux ELF
- `/build_wasm` → 232 KB wasm32-wasi
- `/build_windows` → 1.18 MB PE32+ EXE
- `/build_macos` → 19 KB Mach-O (Intel)
- `/build_target macos-arm64` → 52 KB Mach-O (Apple Silicon)

### Changed — small fixes & perf polish

- `stdlib/std/bytes.nu` — speed-up to the byte-walk helpers used on
  parser hot paths (direct `*u` pointer reads where the bounds check
  is already proven by the loop invariant).
- `stdlib/ext/http_response.nu` — minor allocation-count reduction
  on the response-build path.
- `bench/http_server.nu`, `bench/run.sh`, `bench/run_http.sh` —
  small harness tweaks for the local bench host.
- `README.md` — updated headline benchmark numbers;
  `nurlapi/README.md` added (96-line operator manual for the
  pure-NURL playground + inner-loop dev workflow).
- `examples/{enigma,fizzbuzz,msgpack_demo,wordcount}.nu` — minor
  polish picked up while testing playground rendering.
- `nurlapi/static/viewer.html` — new stdlib / tests source viewer
  (linked from the playground UI).
- `cloudflare/Dockerfile`, `dockerpush.sh`, `startdev.sh` — incidental
  updates so the prod image build & local dev port (8001 vs api/'s
  8000) coexist cleanly.

## [0.9.1] — 2026-05-26

### Summary

- Borrow checker promoted to hard errors by default. Five bug
  classes are compile errors: use-after-move, alias double-free,
  closure escape, aliased mutable-borrow at call sites, iterator
  invalidation. `--no-borrowck` is the escape hatch.
- UDP datagrams (dual-stack IPv4/IPv6 with multicast) + standalone
  DNS resolver (`getaddrinfo` / `getnameinfo`).
- JSON parser ~34× faster — pure-NURL `stdlib/ext/json.nu` rewritten
  around a single-pass scanner; 479 ms → 14 ms on the
  `bench/json_parse` micro-benchmark.
- Peer benchmarks in `bench/` compare NURL with Python / Rust / Node
  on three reproducible micro-benches plus an HTTP-server-vs-Rust-
  hyper / Node-http sweep.
- GitHub Actions workflow with parallel build-test + sanitizer
  (ASan + UBSan) jobs.
- `docs/spec.md` (~1 000 lines) covers the semantic side the grammar
  EBNF does not.
- Generic signal handling, structured logging, silent-miscompile
  diagnostics.

Bootstrap fixed point: stage1 ≡ stage2 byte-identical IR at
1 620 300 B. Full test corpus + sanitizers green.

### Added — UDP datagram sockets + full DNS resolver

Three new public surfaces:

1. **`stdlib/std/udp.nu`** — pure-NURL wrapper over runtime §18b. Dual-
   stack IPv4/IPv6 by default (wildcard `udp_bind("", 0)` creates an
   `AF_INET6` socket with `IPV6_V6ONLY=0` so a single fd serves both
   v4 and v6 peers; literal `udp_bind("127.0.0.1", 0)` stays IPv4-only
   on purpose). Sync + fiber-aware async on every send/recv: inside a
   fiber, `udp_recv_from` / `udp_send_to` park on the reactor on
   EAGAIN; outside any fiber, they fall back to blocking I/O
   transparently. Exposed surface:
   - lifecycle: `udp_bind`, `udp_bind_any`, `udp_connect`, `udp_close`
   - send/recv: `udp_send_to`, `udp_send_str_to`, `udp_recv_from`,
     `udp_send`, `udp_recv` (last two for connected-mode UDP)
   - address: `udp_peer_addr` (borrowed), `udp_local_addr` (owned
     String — how the caller discovers the kernel-assigned ephemeral
     port after `udp_bind("", 0)`)
   - options: `udp_set_timeout`, `udp_set_nonblock`, `udp_set_broadcast`
   - multicast: `udp_join_group`, `udp_leave_group`,
     `udp_set_multicast_ttl`, `udp_set_multicast_loop`. `iface` arg is
     intentionally minimal (IPv4 IP literal or numeric ifindex; no
     `if_nametoindex` so Win32 doesn't need `-liphlpapi`).

2. **`stdlib/std/dns.nu`** — pure-NURL wrapper over runtime §18c.
   System-resolver-based (`getaddrinfo` / `getnameinfo`), no c-ares
   dep. Three entry points:
   - `dns_resolve host` → `! ( Vec String ) NetErr` of A/AAAA literals
     in the kernel's preferred order, dedup'd.
   - `dns_resolve_port host port` → same, but each entry is formatted
     as `"ip:port"` (IPv4) or `"[ip]:port"` (IPv6, RFC 3986 §3.2.2)
     ready for direct `tcp_connect` / `udp_connect`.
   - `dns_reverse ip` → `? String` (Some only when there's a real PTR
     record — `NI_NAMEREQD`).

3. **Runtime §18b / §18c (`stdlib/runtime.c`)** — implementation:
   - `NurlUdp { fd, err_kind, family, peer }` opaque handle (~16 % the
     size of `NurlTcp` — UDP has no TLS state to track).
   - 22 new `nurl_udp_*` and 3 new `nurl_dns_*` exports; WASI stub
     row at the bottom degrades every call to `NetOther` /
     `strdup("")` so `wasm32-wasi` builds still link.
   - Reuses §18's `NURL_NET_ERR_*` error space + `nurl__net_map_errno
     / _wsa` mapping helpers; multicast group-family branching uses a
     new `nurl__parse_numeric_addr` (`AI_NUMERICHOST`) so callers
     don't have to thread family flags through the NURL API.
   - DNS results come back as newline-separated heap strings; NURL
     splits and dedupes are deferred to the wrapper (`__dns_split_lines`).

Acceptance:

- `compiler/tests/udp_basic.nu` — always-on (loopback only, no live
  network). Covers send_to/recv_from roundtrip, peer-addr capture,
  connected-mode send/recv on a separate pair, zero-length datagram,
  wildcard dual-stack bind, broadcast + multicast TTL / loop
  setsockopt smoke. Exit 0, output matches `correct.txt` baseline.
- `compiler/tests/dns_basic.nu` — always-on (uses literals + the
  `/etc/hosts` `localhost` mapping that every Linux/macOS/Win box
  has, no external DNS). Covers resolve + resolve_port for both IPv4
  and IPv6, IPv6 bracketed-port formatting, reverse lookup, empty-
  input → `Err NetOther`.

Runtime LOC delta: `stdlib/runtime.c` 4 790 → 5 606 (+816, +17 %)
including the WASI stub row. Bootstrap fixed point unchanged at
**1 620 300 B** (stage1 ≡ stage2 byte-identical IR) — the runtime
extension is pure stdlib, no compiler IR perturbation.

### Added — HTTP peer-bench (Tier D #3, 2026-05-25)

`bench/run_http.sh` + `bench/http_server.{nu,js}` +
`bench/rust_http_server/` (Cargo + hyper 1.9 + tokio multi-thread)
close the long-standing "no Rust hyper / Node http peer comparison"
gap that critic v0.9.0 §10 flagged. Drives `oha` 1.8.0 against three
hello-world servers at four concurrency levels (1, 10, 50, 200),
median of 3 × 10 s per cell. Captured numbers + commentary in
`bench/HTTP_RESULTS.md`:

| Server  | C = 1    | C = 10   | C = 50   | C = 200  |
|---------|---------:|---------:|---------:|---------:|
| NURL    | 14 451   | **68 960** |  60 897  |  59 044  |
| Rust    | 14 507   |  47 703  | **86 699** | **114 694** |
| Node    |  8 708   |  16 726  |  17 108  |  15 555  |

(req/s, higher is better, best in bold per column.)

Highlights:

- NURL is parity with Rust hyper at C=1 (within < 1 %), and is **1.45× ahead**
  of hyper at C=10 — NURL's 8-worker pool fits the workload while tokio's
  12-worker default is over-provisioned at that concurrency.
- Rust hyper pulls ahead at C ≥ 50, peaking at 115 k/s vs NURL's 59 k/s
  (1.94×) at C=200.
- NURL has **the lowest tail latency across the whole sweep**: p99 0.62 ms
  at C=200 vs Rust's 6.19 ms and Node's 20.95 ms.
- Node http plateaus at ~16 k/s — textbook single-event-loop signature.

The Go `net/http` half of the originally-asked-for comparison is
deferred: Go was not installed on the bench host at capture time.
`bench/run_http.sh` has the lane reserved and `bench/README.md`
documents the gap — a PR adding `bench/http_server.go` would re-publish
a four-column table.

### Added — More examples + refreshed catalogue (Tier D #4, 2026-05-25)

Two-part deliverable closing ROADMAP §6 "More Examples":

1. **`examples/find_clone.nu`** — grep-style recursive search over
   files / directories with three modes:

   ```
   find_clone PATTERN [PATH ...]                  # literal substring
   find_clone --list PAT[,PAT...] [PATH ...]      # comma-separated alternatives
   find_clone --regex PAT [PATH ...]              # POSIX-extended regex
   ```

   PATH is one or more files or directories — directories recurse,
   dotfiles are skipped, and with no PATH the tool reads stdin. Output
   is `path:line:contents` per match; exit 0 on any match, 1 on no
   match, 2 on usage / I/O error. Closure-shaped matchers
   (`make_literal_test`, `make_list_test`, `make_regex_test`) so
   `scan_lines` is mode-agnostic; `walk_dir` returns -1 on
   not-a-directory so the dispatcher falls back to the file scanner
   cleanly. Built on top of `stdlib/std/fs.nu` (`read_file`,
   `dir_list`), `stdlib/ext/regex.nu` (`regex_compile` / `_test`), and
   the existing `nurl_str_*` helpers. Pure CLI I/O — runs on the
   public playground.

2. **`examples/README.md` refresh** — from a 3-of-36 catalogue to all
   36 rows, organised by category (CLI tools / Algorithms / Data
   formats / Language showcase / HTTP & RPC / LLM API / SDL canvas).
   Each row carries a one-line description plus a **playground** or
   **local** tag describing where it can run. *playground* = pure
   compute + stdin / argv / file I/O (runs on `play.nurl-lang.org`
   as-is); *local* = needs network, a server listening port, an
   `ANTHROPIC_API_KEY`, SDL2, or microphone access.

The critic-suggested agent-loop variants and MCP-client demo were
deliberately omitted: `examples/claude_agent.nu` already covers the
agent shape, and an MCP-client-from-the-public-playground would need
either secret injection (API keys) or WASM outbound sockets,
neither of which the playground exposes today.

### Added — GitHub Actions CI (critic v0.9.0 Tier D #2, 2026-05-25)

`.github/workflows/ci.yml` lifts the previously-local build + test +
sanitiser gate to PR-level. Two parallel jobs on `ubuntu-latest`:

- **`build-test`** — installs clang + optional FFI dev libs
  (`libcurl4-openssl-dev`, `libssl-dev`, `libsqlite3-dev`,
  `libpq-dev`, `zlib1g-dev`, `libzstd-dev`) so every
  `stdlib/runtime.<lib>` sentinel lights up, then runs `./build.sh`
  (bootstrap stage1 ≡ stage2 fixed point + the full `run_tests.sh`
  corpus). 15-min timeout.
- **`sanitizers`** — same setup, runs `./build.sh --san --no-tests`
  to build an ASan + UBSan-instrumented stack, then
  `compiler/tests/run_san_tests.sh` over the corpus. 25-min timeout.

Triggers on push to `main` / `Improvements`, PR-to-`main`, and
`workflow_dispatch` (manual rerun). `concurrency.cancel-in-progress`
cancels older runs when a new commit lands on the same ref so the
queue can't fill up on a fast-typing day.

`nurlfmt --check` is deliberately NOT yet wired up — ~100 .nu files
in the current stdlib / tests / examples corpus (and
`compiler/nurlc.nu` itself) are not in canonical form, so adding the
check today would fail every PR with an unrelated 100-line diff.
The follow-up path is documented inline in the workflow comments:
either a single repo-wide `nurlfmt --write` pass first, or grow the
check scope file-by-file as canonicalisation lands.

### Added — Structured logging (critic v0.9.0 Tier D #1, 2026-05-25)

`stdlib/std/log.nu` gains two structured-logging features that the
critic flagged as missing-for-v1.0 (ROADMAP §2):

1. **Key/value variants** — `log_debug_kv1` / `_kv2` / `_kv3`,
   `log_info_kv1..3`, `log_warn_kv1..3`, `log_error_kv1..3`. Twelve
   fixed-arity helpers that accept 1..3 `s` key / `s` value pairs
   alongside a message. Same below-threshold suppression as the raw
   and `fN` variants.

2. **JSON output mode** — `log_set_json T` / `log_set_json F`,
   `log_get_json`. When JSON is on, every `log_*` call emits a single
   `{"level":"info","msg":"…","key":"value",…}` line instead of the
   `[INFO]  msg key=value` text form. Compatible with `jq`, Logstash,
   Loki, CloudWatch, etc. — values are RFC 8259-compliant (named
   escapes for `"` `\` `\n` `\r` `\t`; remaining control bytes
   0x00..0x1F emit `\u00XX`).

The existing raw `log_<level>` and `log_<level>fN` calls route
through the new shared `__log_dispatch` so JSON mode applies
uniformly to every call site. The per-byte JSON-escape walker uses
a `*u` pointer instead of `nurl_str_get` to avoid the O(strlen)
per-character cost. Compiler / bootstrap untouched; regression
`compiler/tests/log_structured.nu` exercises text mode, JSON mode,
escape coverage and below-threshold suppression. `jq -c .`
round-trips every JSON line emitted by the test.

### Added — Tier A diagnostics for the v0.9.0 critic (2026-05-25)

Closes the four "grammar-legal but semantically dead" cases the
external review flagged as silent compiles. Each is a small, local
compiler change; bootstrap fixed point holds (stage1 ≡ stage2
byte-identical IR at **1 620 300 B**); full test corpus green.

1. **`^` vs `^^` XOR confusion `warning:`** — `gen_ret` peeks the
   token after the returned expression. If it is on the same source
   line as the `^` AND is value-producing (not `:` / `=` / `;` / `}`
   / `)` / `]` / `{` / EOF), the user almost certainly wrote `^ X Y`
   intending XOR. Emits a soft `warning:` naming `^^` (two adjacent
   carets, no space) as the cure. Test: `should_warn_caret_xor.nu`.
2. **Bare-callable-as-statement `error:`** — `gen_stmt` checks for
   `name args` (no parens) at statement position. If `name` is a
   known callable (registered in syms with no `__ptr` / `__global`
   / `__param`), dies with `( name args )`-cure pointer. The
   companion `gen_ffi_decl` now stamps `<name>__ffi = 1` so FFI
   builtins like `nurl_print` are detected alongside @-fns. Test:
   `should_fail_bare_ident_stmt.nu` (PoC: `nurl_print \`oops\``).
3. **Use-after-`_free` via wrapper `error:`** — auto-infer `sink`
   convention on parameters that a function passes to a destructor
   (`*_free`) or to another fn's existing `sink` slot. New helper
   `bck_record_inferred_sink` accumulates into
   `__fn_inferred_sink__` per fn body; `gen_fn_decl_concrete`
   merges into `g_fn_sink[fname]` after body parses, deduping
   against the explicit `sink` marker. Closes the indirect
   `( take s ) ( read s )` use-after-free the critic exhibited.
   Test: `should_fail_uaf_indirect.nu`. Also added
   `str_word_index` helper next to `str_contains_word`.
4. **Per-instantiation source line for generics** — replaces the
   opaque `<generic>:1:21:` synthetic filename with
   `<generic vec_as_slice__i64 from user.nu:42>:1:21:` so a parse
   error during the substituted-body re-parse names the call site
   in the user's own code. `defer_instantiation` now captures the
   call-site file + line; `flush_deferred_instantiations` passes
   them to `emit_one_instantiation`, which builds the synthetic
   filename. (Diagnostic-only — IR unchanged.)

### Changed — `stdlib/ext/json.nu` parser ~34× faster (2026-05-25)

`json_parse` of the `bench/json_parse` payload (5 × 64 KB) dropped
from **479 ms** to **14 ms** — now faster than Python's C-extension
`json` (~34 ms) and within ~3× of a hand-written zero-copy Rust
parser (~5 ms). Two landed changes:

1. **Direct `*u` pointer reads instead of `nurl_str_get`.** Every
   `__jp_peek` was paying a full `strlen` of the whole input (the
   `core/string.nu` helper does an `strlen` for the bounds check) —
   a 64 KB parse spent gigabytes of memory bandwidth in `strlen`
   alone, classic O(n²). Replaced with a cached `*u`-based byte read
   against `. p src`, plus a `memchr`-driven fast path in
   `__jp_parse_string` that slices the literal byte range when the
   string contains no `\` escape (the common case).

2. **Packed-layout `String` constructor.** New
   `core/string.nu::string_from_bytes_packed` allocates the 24-byte
   `Vec` control block and the data buffer in a single
   `nurl_alloc(24 + n + 1)`. `vec_free` / `vec_free_with` /
   `__vec_grow` in `core/vec.nu` detect the layout by `data ==
   ctl + 24`; the lifecycle is byte-identical to a normal String
   (it can still grow — the first growth pays for an unpacking copy
   out into a separate buffer). For JSON parsing every `JNum` /
   `JStr` is read-only after construction, so this exact case halves
   the per-string allocation count.

Bench runner (`bench/run.sh`) also stopped forking `date` twice per
measurement by switching to `$EPOCHREALTIME` arithmetic (bash 5+),
shaving ~3 ms of measurement overhead per cell.

`bench/RESULTS.md` and `README.md` updated with the new headline
numbers. Bootstrap fixed point holds; full test corpus green;
no API or grammar changes.

### Added — `bench/` peer-comparison benchmark suite (2026-05-25)

Three reproducible micro-benchmarks with one source file per language
(NURL, Python 3, Rust, Node.js):

* `bench/lcg.{nu,py,rs,js}` — 100M-step MMIX linear congruential
  generator. Tight i64 multiply + add with a single-stream data
  dependency that defeats LLVM's closed-form folding.
* `bench/sieve.{nu,py,rs,js}` — Sieve of Eratosthenes computing
  π(10 000 000) = 664 579. Memory bandwidth + branch prediction.
* `bench/json_parse.{nu,py,rs,js}` — 5 parses of a deterministic
  ~64 KB JSON file. Each language uses **what ships in its standard
  distribution** (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`; Rust links a small hand-written
  recursive-descent parser since it has no JSON in stdlib).

`bench/run.sh` compiles each NURL + Rust target, runs every present
language N times (default 5) with a per-run `timeout`, and prints a
median-wall-clock-ms table. Missing tools render as `n/a`; a cell that
hits the timeout renders as `>30s` instead of hanging the suite.

`bench/RESULTS.md` captures the numbers from one specific machine:

* On `lcg` and `sieve` NURL lands within measurement noise of Rust —
  same LLVM `-O2 -flto` codegen on both sides.
* On `json_parse` NURL's pure-NURL parser is ~12× slower than Python's
  C `json` and ~50× slower than a hand-written Rust parser. The
  module's allocator-and-Vec-growth path through recursive descent is
  the explanation, and a zero-copy slice-based rewrite would close
  most of the gap — tracked as a follow-up.

An HTTP-server-vs-`net/http` peer benchmark is not included; that
would need a Go install and a `wrk`-shaped harness.

### Changed — borrow-checker diagnostics are now hard errors

* `bck_diag` (use-after-move) and `bck_esc_warn` (escape analysis +
  aliased-mut + iterator invalidation) emit `: error: ` instead of
  `: warning: ` and bump a new `g_bck_errors` counter. `main()` exits
  non-zero after `parse_program` if any violation was recorded —
  every error surfaces in one run (same shape as a C compiler).
* The test harness now treats `borrow_*` tests as expected compile
  failures with an `ERRORS` baseline blob rather than "compile OK +
  WARNINGS". The exact error text remains regression-protected.
* `--no-borrowck` remains the escape hatch; the abort message points
  at it so a user hitting a false positive is never wedged.
* Bootstrap fixed point holds (the checker is diagnostic-only — IR is
  byte-identical with or without `--no-borrowck`): stage1 ≡ stage2 at
  **1 602 394 B**.

Five bug classes are now compile errors by default: use-after-move,
alias double-free, closure escape, call-site aliased mutation, and
iterator invalidation. `*T` raw pointers and aliased mutation through
nested-argument reads remain unchecked; see
[`docs/MEMORY.md`](docs/MEMORY.md).

## [0.9.0] — 2026-05-24

### Changed — `refactor/nurlify` branch

Picks up where `refactor/pure-nurl` left off and drives `stdlib/runtime.c`
the rest of the way down:

* **`stdlib/runtime.c`: 6 265 → 4 540 LOC (−1 725, −27.5 %).** Combined
  with the prior branch the total reduction since v0.8.0 is **8 879 →
  4 540 LOC (−4 339, −48.9 %)** — over half of the C runtime is gone.
  Bootstrap fixed point held on every shipped phase; full test corpus
  green.
* **PURIFY §17 random.** `rand_u64` / `rand_hex_str` ported to pure
  NURL in `stdlib/std/random.nu`. Only `nurl_rand_fill` stays C —
  the `getrandom` / `arc4random_buf` / `BCryptGenRandom` platform
  branching is genuinely syscall-shaped FFI.
* **PURIFY §4 file ops batch.** `nurl_read_file_bytes` /
  `_write_file_bytes` / `_file_read_chunk` / `_read_n_bytes` /
  `_errno_kind` moved to pure NURL. The `g_last_bytes_len` sideband is
  gone — `fread` / `fwrite` write directly into the `Vec[u]` data
  buffer and `vec_set_len` records the count. `EACCES` / `EPERM` /
  `EEXIST` added to `nurl_native_constant`; `errno_kind` now lives in
  `stdlib/core/posix.nu`.
* **PURIFY §22 gzip.** `nurl_gzip_compress` / `_decompress` moved to
  pure-NURL FFI in `stdlib/ext/compress.nu` over `deflateInit2_` /
  `deflate` / `deflateEnd` + `inflateInit2_` / `inflate` /
  `inflateEnd`. Two tiny C accessors (`nurl_z_setup` /
  `nurl_z_total_out`) bridge the platform-varying `z_stream` field
  layout (LP64 vs LLP64 `uLong` width).
* **PURIFY §14 HTTP response accessors.** The 7 accessor C functions
  (`status` / `err_kind` / `body` / `body_len` / `header_count` /
  `header_name` / `header_value`) deleted from `runtime.c`. Pure-NURL
  equivalents in `stdlib/ext/http.nu` read the `NurlHttpResponse`
  heap struct via `nurl_peek(p, slot)` over its 6-i64 slot layout.
  Static asserts in `runtime.c` pin the layout at compile time so a
  future field reorder breaks the native build instead of silently
  miscompiling NURL reads. `nurl_http_response_free` stays C because
  it walks `headers[]` deallocating each name / value pair plus the
  body.
* **PURIFY §14b HTTP libcurl backend** + multi-stream orchestration
  driven from pure NURL. Sync `nurl_http_perform_full_to` and
  multi-stream `_open_to` / `_next` / `_pump_headers` plus the 5
  stream accessors live in `stdlib/ext/http.nu`; 22 monomorphic
  trampolines stay C (`nurl_curl_*` `setopt` / `multi` /
  stream-state) because libcurl's variadic `curl_easy_setopt` and the
  raw-fn-pointer callbacks (`nurl__http_write_body` /
  `_write_header`) can't cross the FFI directly. `NurlHttpStream`'s
  three historical `int` fields widened to `long long` for a clean
  14×i64 slot layout; `static_assert` pins it. Live verified
  against httpbin.
* **PURIFY §2 SIMD CSV scanner** ported to pure NURL
  (`stdlib/ext/csv.nu`, −508 C). The vectorised newline / delimiter
  scanner is now NURL @-fns over `nurl_peek` of a heap-side byte
  window.
* **`runtime.c` prose cleanup** (commits `d558844`, `f88d7bb`):
  trimmed verbose multi-paragraph explanations, phase-by-phase
  migration history and prose that just restated what the code does
  — kept one-line function-purpose intros and the non-obvious "why"
  notes (TLS / SNI race discipline, fiber park-unlock ordering,
  wasm32 layout caveats, libz LP64 / LLP64 differences). Net −913
  comment-only LOC.

### Changed — `JSON-to-production` branch

* **`json` ext goes production-ready.** `stdlib/ext/json.nu`:
  - **Typed `JsonError`** replaces the bare `ParseErr` — carries
    `kind` (`BadFormat` / `Empty` / `TrailingGarbage` / `Overflow`),
    `pos` (0-based byte offset), `line` (1-based) and `col`
    (1-based). Location is computed once per failure and travels
    with the error value — no global state, so nested
    `json_parse` calls and multi-threaded use are both safe.
    `json_format_error` renders the standard message; build your
    own from the fields if you need a custom shape.
  - **RFC 8259 strict mode.** Non-conforming numbers (leading zeros
    like `01`, `+5`, lone `.5`, `1.`) are now `BadFormat` instead of
    parsing to the prefix — `json_stringify ∘ json_parse` is
    guaranteed-valid JSON.
  - **New constructors** — `json_int n` / `json_float x` from
    primitives (no `i8*` roundtrip), `json_arr_new` / `json_obj_new`
    for empty containers.
  - **Duplicate-key behavior documented.** Parser preserves
    duplicate keys as-is; `json_obj_get` returns the first match in
    source order; `json_obj_set` replaces the first match in source
    order.
  - Call sites updated across `stdlib/ext/anthropic.nu`,
    `stdlib/ext/mcp{,_client,_http,_stdio}.nu`, `nurlapi/main.nu`,
    `examples/serde_demo.nu`, `tools/nurl-lsp/jsonrpc.nu`.

### Changed — `refactor/pure-nurl` branch

The `refactor/pure-nurl` branch took the bulk of `stdlib/runtime.c`
out of C and into pure NURL — either as pure-NURL @-fns or as direct
`& \`c\`` / `& \`pthread\`` / `& \`sqlite3\`` FFI declarations.

* **`stdlib/runtime.c`: 8 879 → 6 265 LOC (−2 614, −29.4 %).** The
  bootstrap fixed point held on every shipped phase and the full
  test corpus stayed green.
* **Python removed from the bootstrap.** `compiler/nurlc.py` and
  `compiler/src/*.py` are gone. Stage 0 now links the committed
  `compiler/nurlc_lastgood.ll` snapshot directly via clang. The
  only build-time dependency is clang/LLVM 14+. Refresh the
  snapshot with `./build.sh --refresh-bootstrap` when a
  grammar/runtime-ABI change leaves the current snapshot unable
  to compile current `nurlc.nu`.
* **`Box[T]` / `Cell[T]` / `Rc[T]` / `Arc[T]`** heap-stable
  allocator surface — `stdlib/core/box.nu`, `stdlib/core/cell.nu`,
  `stdlib/std/rc.nu`, `stdlib/std/arc.nu`. `% Drop` auto-fires;
  `nurl_native_sizeof` + `nurl_atomic_i64_*` runtime primitives
  added. This unblocked Phases 6 / 8 / 11 / 12 of the purification.
* **Per-phase migration:**
  - Phase 1 §3 char classification (`stdlib/core/char.nu`, −11 C)
  - Phase 2 §15 logging level (`stdlib/std/log.nu`, −7 C)
  - Phase 3 §11 libm + integer helpers (`& \`m\`` / `& \`c\`` FFI, −17 C)
  - Phase 4 §17 crypto MD5/SHA-1/256/512 + HMAC
    (`stdlib/std/hash_*.nu`, **−541 C**)
  - Phase 5 §2 string ops over libc (strlen/strcmp/strncmp/strstr/
    memcmp/memmem/atoll/atof/memcpy/strdup via preamble, **−682 C**)
  - Phase 6 §19 threads / mutex / cond (pthread `& \`pthread\``
    FFI in `stdlib/std/thread.nu`, −162 C; mingw-w64 winpthreads
    linked via `-lpthread`)
  - Phase 7 §4 + §13 file & dir syscalls — incremental over many
    batches (realpath / write_file_safe / file_size / mmap / fread
    fallback / dir_list POSIX, −158 C combined)
  - Phase 8 §16 + §16b process spawn (fork/exec/poll, `||` and
    `&&` added as language tokens for the spawn-error sideband,
    **−245 C**)
  - Phase 9a §7 + §8 codegen counters + last-type sideband
    (pure-NURL @-fns in `nurlc.nu`, −71 C)
  - Phase 9b §6b symbol table (3 parallel grow-by-2× arrays,
    inner loops via direct `*s` / `*i` pointer arithmetic, −72 C;
    ~0.95× of C runtime — LTO inlines everything and the parallel
    layout is cache-friendlier than the C interleaved struct)
  - Phase 9c §5 HashMap deleted entirely (the canonical
    `stdlib/std/hashmap.nu` HashMap[s i] is the one-true map for
    every consumer; the migration also fixed `hash_string` from
    O(n²) → O(n) by switching from per-byte `nurl_str_get` to a
    direct `*u` byte walk, −101 C)
  - **Phase 10 §6a Lexer (the big one, −592 C).** Full state
    machine + 4-deep lookahead ported to pure-NURL @-fns over a
    280-byte heap handle. Uncovered + fixed a subtle escape-handling
    bug: only `\n \t \r \\` are real escapes; any other `\X`
    (including `` \` ``) writes the lone `\` and advances one byte.
  - Phase 11 §23 DoS protection (`stdlib/std/dos.nu`, −180 C)
  - Phase 12 §21 SQLite bridge — pure-NURL FFI over 18 libsqlite3
    symbols (`stdlib/ext/sqlite.nu`, **−330 C**)
  - §12 Time — `clock_gettime` + `nanosleep` FFI (`stdlib/std/time.nu`,
    −38 C; macOS uses `CLOCK_MONOTONIC = 6` vs `1` elsewhere, read
    at runtime via `nurl_native_constant`)
  - §13 batch 2/3 — stdin + dir_list POSIX FFI (−80 C)
  - §11 strtod sideband eliminated with an endptr buffer (−20 C)
* **`||` and `&&` operators** added as language tokens — strict
  binary, bool-only short-circuit. Alternative to the chainable
  `|` / `&` for cases that are more readable as a `||` / `&&`
  chain. Grammar v2.0 documents them. Same LLVM IR as `|` / `&`
  on i1 left operands.
* **`./check.sh <file.nu>`** — per-file syntax/type check tool;
  runs `nurlc` against a single source file in ~0.2 s vs build.sh
  ~60 s. Use in iterate-fix loops before kicking the full build.
* **Test runner output split** into `success.txt` + `failures.txt`
  so a failed test is greppable without scrolling through the
  green output.
* **Parenthesised-operator diagnostic.** A `(` begins a call, so
  `( . obj field )` / `( | a b )` / `( + x y )` etc. now produce
  a precise call-site `error:` instead of a far-away LLVM-verifier
  complaint. (Listed earlier in this section under the original
  feature work; reiterated here as it landed in this branch.)
* **Call-arity diagnostics.** Every call's argument count is
  checked against the callee's declared parameter count; a
  mismatch points at the call site (same listing remark).
* **Prefix arity-cascade diagnostic.** Short-an-argument prefix
  operator over-reads now name the offending token and point back
  at the line where the cascade started.
* **`mcp_response_get_result`** — `mcp_client`'s 1-arg result
  extractor renamed for consistency with the rest of the surface.

### Fixed — `refactor/pure-nurl` branch

* **WASM FFI width mismatches** uncovered by uuidgen wasm build
  (2026-05-24). `nurl_errno_get` / `nurl_errno_set` /
  `nurl_wait_is_exited` / `_exit_status` / `_is_signaled` /
  `_term_sig` paluut + parametrit widened `int` → `long long`
  in `stdlib/runtime.c`. On x86_64 SysV the `int` return's upper
  32 bits were undefined and accidentally zero; wasm-ld validates
  signatures strictly and refused to link until the C side
  agreed with the NURL FFI's `→ i` (i64) declaration. `memmem`
  added to `api/app/main.py:LIBC_WASM32_ABI` (the playground's
  wasm-build IR rewriter), since wasm32 `size_t` is i32 but
  `nurlc.nu`'s preamble emits `memmem(i8*, i64, i8*, i64)`.
* **macOS `WIFEXITED` lvalue requirement.** The widened
  `nurl_wait_*` functions originally passed `(int)status` as an
  rvalue to the W*-macros; macOS's `<sys/wait.h>` expands them
  to `*(int*)&(x)` which needs an lvalue. Fixed by binding
  `int s = (int)status;` first inside each wrapper. Restores the
  zig macOS-arm64 / macOS-x64 cross-build.

### Added

* **MsgPack serde.** `stdlib/ext/serde.nu` gained `from_msgpack_i` /
  `from_msgpack_f` / `from_msgpack_b` / `from_msgpack_string` —
  decoding MessagePack bytes straight to a built-in value. There is no
  `% MsgpackSerialize` trait: MessagePack and JSON share a data model,
  so a value is encoded by composing the existing `to_json` with
  `msgpack_encode`. The decoders return `!T MsgpackErr` (not
  `ParseErr` — `MsgpackErr` is the richer error type and represents
  every failure losslessly); `MsgpackErr` gained a
  `MsgpackTypeMismatch` variant for a value that decoded cleanly but
  is the wrong shape. Demo `examples/msgpack_demo.nu`; regression
  `compiler/tests/msgpack_serde.nu`. With this the serde story covers
  JSON, TOML and MessagePack — all reusing one `JsonSerialize` impl
  per type.

* **TOML serde.** `stdlib/ext/serde.nu` gained its TOML side: a
  `% TomlSerialize [T] { @ to_toml T x → TomlValue }` trait with impls
  for `i` / `b` / `s` / `String`, and `from_toml_i` / `from_toml_b` /
  `from_toml_string` decoders returning `!T ParseErr` — the same shape
  and error type as the JSON helpers. There is no `f` impl: the
  `TomlValue` AST has no float variant. `stdlib/ext/toml.nu` gained
  `toml_stringify`, the inverse of `toml_parse`: a `TomlValue` is
  rendered as TOML text — top-level `key = value` lines, nested tables
  and arrays inline, strings escaped with the `\\ \" \n \r \t` set the
  parser accepts, so `toml_parse ∘ toml_stringify` round-trips.
  Regression `compiler/tests/toml_serde.nu`; verified leak-free under
  ASan/UBSan/LSan.

* **MessagePack codec.** `stdlib/ext/msgpack.nu` is a faithful binary
  codec between the `Json` value and the MessagePack wire format:
  `msgpack_encode Json → ! ( Vec u ) MsgpackErr` and `msgpack_decode
  ( Vec u ) → ! Json MsgpackErr`. The encoder emits the smallest
  signed integer format, float64 for reals, and length-appropriate
  str / array / map headers; the decoder accepts every integer and
  float format plus all str / array / map sizes. `bin` / `ext` and
  non-string map keys are reported as `MsgpackUnsupported`; truncation
  and malformed input have their own `MsgpackErr` variants; a
  recursion cap guards both directions. Three runtime helpers —
  `nurl_f64_bits`, `nurl_f64_from_bits`, `nurl_f32_from_bits` — provide
  the IEEE-754 bit access needed for the float wire format. Regression
  `compiler/tests/msgpack_basic.nu` (37 assertions: round-trips,
  msgpack.org encode vectors, non-canonical-format decoding, malformed
  inputs); verified leak-free under ASan/UBSan/LSan. First of the
  three Serde-completion ships (codec, then TOML serde, then MsgPack
  serde).
* **Runtime float-bits helpers** — `nurl_f64_bits`,
  `nurl_f64_from_bits`, `nurl_f32_from_bits` in `stdlib/runtime.c`.
* **Parenthesised-operator diagnostic.** A `(` begins a function call,
  so the token after it must be a function name. An operator token
  there — `( . obj field )`, `( | a b )`, `( + x y )` — meant an
  operator expression was wrongly wrapped in parentheses. nurlc used
  to take the operator's lexeme as the callee, emit a call to a
  function literally named `.` / `|` / `+`, and let the build fail far
  from the source at link time with `use of undefined value`.
  `gen_call` now rejects a binary operator, member access `.`, the
  cast `#` or the caret `^` immediately after `(` with a precise
  `error:` at the call site — `operator '.' cannot be a call target:
  '(' begins a function call, but operator expressions are written
  without parentheses` — and a caret on the operator. Regression
  `compiler/tests/should_fail_paren_operator.nu`.

* **Typed Path.** `stdlib/std/path.nu` gained a `Path { String inner }`
  typed, owning wrapper over a path string, with a concise
  Rust-PathBuf-style verb API — `path_new`, `path_str` (borrow the
  inner buffer), `path_len`, `path_is_empty`, `path_clone`,
  `path_free`, `path_eq`, `path_push` (join one component),
  `path_parent`, `path_name`, `path_is_abs` — and the two operations
  the existing string-level layer lacked: `path_canonical` (realpath:
  absolute, symbolic links resolved) and `path_relative_to` (a purely
  lexical relative path between two paths). Both return `? Path` —
  None for a missing / inaccessible path or a not-comparable pair. The
  string-`s`-based `path_*` functions stay the raw layer underneath;
  the typed functions never consume their arguments. One runtime
  helper, `nurl_realpath`, is reached through the pure-NURL `& \`c\``
  FFI model, so the compiler is unchanged and the bootstrap fixed
  point is byte-identical. Regression `compiler/tests/path_typed.nu`;
  verified leak-free under ASan/UBSan/LSan.
* **Runtime helper** — `nurl_realpath` (realpath on POSIX, `_fullpath`
  on Windows) in `stdlib/runtime.c`.
* **Extended hash family — SHA-512, MD5, HMAC-SHA-512.**
  `stdlib/std/hash.nu` gained `sha512_bytes` / `sha512_hex` (FIPS 180-4
  SHA-512, 64-byte digest), `md5_bytes` / `md5_hex` (RFC 1321 MD5,
  16-byte digest) and `hmac_sha512_bytes` / `hmac_sha512_hex` (RFC 2104
  HMAC over SHA-512). All are binary-clean — they take `( Vec u )` and
  are length-aware, so NUL bytes are preserved — mirroring the existing
  `sha1_bytes`. The three algorithms are self-contained in
  `runtime.c` §17 (no libsodium / OpenSSL dependency) and are reached
  through the pure-NURL `& \`c\`` FFI model, so the compiler is
  unchanged and the bootstrap fixed point is byte-identical. MD5 and
  SHA-1 are documented as compatibility-only — both are collision-broken
  and must not authenticate data or hash secrets. Regression
  `compiler/tests/hash_extended.nu` checks every algorithm against
  published vectors (RFC 1321 §A.5, FIPS 180-4, RFC 4231 HMAC cases
  1/2/6); verified leak-free under ASan/UBSan/LSan.
* **Runtime hash primitives** — `nurl_md5_bytes`, `nurl_sha512_bytes`,
  `nurl_hmac_sha512_bytes` in `stdlib/runtime.c`.
* **Advanced filesystem operations.** `stdlib/std/fs.nu` gained
  recursive directory operations and a streaming file reader:
  `dir_create_all` is mkdir -p — it creates every missing parent
  directory and treats an already-existing directory as success;
  `dir_remove_all` is recursive rm -rf — it walks the tree removing
  every entry before removing the directory itself, and unlinks a
  symlink rather than descending through it. `file_open` /
  `file_read_chunk` / `file_eof` / `file_close` read a file in
  fixed-size byte chunks over a new `File` handle, so a binary input
  far larger than RAM can be processed without ever being fully
  resident (line-oriented streaming stays with `stdlib/std/bufio.nu`).
  Three new `runtime.c` filesystem helpers back this — `nurl_path_type`
  (an lstat-based entry classifier), `nurl_file_read_chunk` and
  `nurl_file_eof` — all reached through the pure-NURL `& \`c\`` FFI
  model, so the compiler is unchanged and the bootstrap fixed point is
  byte-identical. Regression `compiler/tests/fs_advanced.nu`; the new
  paths are verified leak-free under ASan/UBSan/LSan.
* **Runtime filesystem helpers** — `nurl_path_type`,
  `nurl_file_read_chunk`, `nurl_file_eof` in `stdlib/runtime.c`.
* **Call-arity diagnostics.** `gen_call` now checks every call against
  the callee's declared parameter count and rejects a mismatch with a
  precise `error:` at the call site — e.g. `call to 'add' has the
  wrong number of arguments: expected 2, got 1`. Previously a
  wrong-arity call to a known function either miscompiled silently
  (too few arguments) or emitted a malformed `call` the LLVM verifier
  complained about far from the source (too many). `scan_fn_sigs`
  records each non-generic `@`-function's parameter count through a
  new pure-lexical type skipper (`scan_skip_type` — no `parse_type`
  call, which would desync the scan); a name carrying two definitions
  of differing arity is marked ambiguous and skipped rather than
  mis-blamed. Generic and variadic-FFI callees are out of scope for
  v1.
* **Prefix arity-cascade diagnostic.** When a prefix operator runs out
  of operands and over-reads into the following statement — the
  classic NURL cascade, since operators have fixed arity and no
  closing bracket — the resulting "unexpected token" error now names
  the offending token and points back at the line where the
  short-an-argument statement began, instead of blaming the innocent
  next line.
* **Compiler regressions** — `compiler/tests/{call_arity_ok,`
  `should_fail_call_arity_few,should_fail_call_arity_many,`
  `should_fail_prefix_cascade}.nu`.
* **MQTT client — topic-filter wildcard matching.** `mqtt_topic_matches`
  in `stdlib/ext/mqtt.nu` implements the MQTT 5.0 §4.7 `+` / `#`
  wildcard rules — `+` matches one topic level, `#` matches the
  remainder (zero levels included, so `sport/#` also matches the parent
  `sport`) — including the §4.7.2 guard that a filter beginning with a
  wildcard never matches a `$SYS/...` topic. The intended use is
  client-side dispatch when one connection carries several
  subscriptions.
* **MQTT offline codec regression** — `compiler/tests/mqtt_codec.nu`
  exercises the Variable Byte Integer round-trip, the unsigned byte
  reader, MQTT UTF-8 string framing, the CONNECT byte layout, CONNACK
  reason extraction, MQTT 5 user-property parsing, the typed `MqttErr`
  names, and topic matching — no network, CI-safe.

## [0.8.1] — 2026-05-21

### Added

* **Playground multi-target cross-compilation.** The `api/` browser
  playground replaces its four fixed build buttons (WASM / native /
  Windows / macOS) with a grouped **Target** dropdown + one **Build**
  button. New compile targets, all driven by the `zig cc` pipeline
  already shipped for macOS:

  * `linux-x64-musl`, `linux-arm64-musl`, `linux-riscv64-musl` —
    fully-static ELF (runs on any Linux of that arch, no libc pin).
  * `linux-arm64-gnu` — dynamic glibc 2.31+ ELF.
  * `macos-x64`, `macos-arm64` — Mach-O; Apple Silicon was previously
    unreachable (the only macOS target was Intel).

  Backed by `POST /build_target` (target id in the body) and
  `GET /targets` (the registry the UI builds its dropdown from); the
  three near-duplicate build endpoints now share one `_build_zig_cross`
  helper. `POST /build_macos` is kept as a thin wrapper for MCP / older
  clients. The MCP server (both `/mcp` and the REST companion) gains a
  `nurl_build_target` tool — valid target ids are inlined as a schema
  enum so clients need no separate lookup; the existing per-OS build
  tools are unchanged. canvas/audio FFI is rejected on the cross
  targets and HTTP falls back to the runtime's no-op stubs — same
  contract macOS had.

  Image cost is ~negligible: zig already bundles musl / glibc /
  libSystem for every arch, so each target adds only one ≈125 KB
  `runtime.<id>.o`. The Dockerfile cross-compiles those at build time
  and **pre-warms** each target's libc/compiler-rt into a baked
  `ZIG_GLOBAL_CACHE_DIR`, so the first build per target is a fast
  cache hit rather than a cold multi-second libc compile; the warm
  link doubles as a build-time smoke test. No `riscv64` glibc target —
  zig 0.13's bundled glibc for RISC-V is incomplete; `riscv64-musl`
  covers RISC-V until the image moves to zig ≥ 0.14.

* **`stdlib/std/time.nu` calendar completion.** On top of the existing
  `Time` struct and Hinnant `civil_from_days` conversions:

  * `is_leap_year`, `days_in_month` (leap-aware), `time_yday` (1..366).
  * `time_make Y Mo D H Mi S` — range-checked civil-time constructor
    (rejects e.g. 2023-02-29 and month 13).
  * `time_cmp` / `time_eq` / `time_before` / `time_after` — order
    timestamps (by Unix-second value).
  * `time_add_seconds` / `time_add_days` (negative subtracts; rolls
    month/year/leap-day over) / `time_diff_seconds`.
  * `time_format t fmt` — strftime subset (`%Y %y %m %d %H %M %S %j
    %a %A %b %B %%`), alongside the fixed `time_format_iso` /
    `time_format_http`.

  Regression `compiler/tests/time_calendar.nu`; `calendar_time.nu`
  updated. All pure NURL arithmetic, ASan/UBSan/leak-clean.

* **Buffered streaming reader — `stdlib/std/bufio.nu`.** `BufReader` pulls
  a file (or stdin) through a 64 KiB buffer one `fread` at a time, so an
  input far larger than RAM is processed without ever being fully
  resident — the streaming counterpart to `read_file` / `csv_reader_new`,
  which load the whole file first. Built for fast ETL over logs / CSV /
  JSONL:

  * `bufreader_open path → ! BufReader IoErr`, `bufreader_stdin → BufReader`.
  * `bufreader_read_line br → ? String` — a fresh owned line each call,
    `\n` / `\r\n` stripped; `None` at EOF.
  * `bufreader_read_line_into br dst → b` — refills the *caller's* String
    with the next line, so a steady-state read loop allocates nothing
    after warm-up (one `memcpy` per line, no `malloc`). The recommended
    ETL hot path.
  * `bufreader_eof`, `bufreader_close`.

  Line terminators are found with `memchr` (glibc SIMD), not a byte loop.
  Lines longer than the buffer grow it; lines straddling a refill
  boundary are compacted with `memmove`. Neither read entry point hands
  back a pointer into the internal buffer, so there is no
  invalidated-view foot-gun. Implemented as pure-NURL `& \`c\`` FFI
  (`fread` / `memchr` / `memmove` / `fdopen`) — no `runtime.c` change.
  New supporting primitive `string_push_bytes` (`stdlib/core/string.nu`)
  appends a known-length raw byte range to a String. Regressions
  `compiler/tests/bufio_basic.nu` (mixed terminators, empty + trailing
  unterminated line, missing-file error) and `bufio_stream.nu` (50 001
  lines across ~17 refills + a 200 000-byte line forcing buffer growth);
  both ASan + UBSan + leak-detection clean.

* **Standard-library Clone story.** Owned containers can now be deep-copied
  without hand-rolling a per-type clone. NURL has no type-class dispatch,
  so — exactly like the existing `vec_free` / `vec_free_with` split — the
  clone is delivered as a per-call closure rather than a language-level
  `Clone` trait:

  * `string_clone String → String` (`stdlib/core/string.nu`) — independent
    deep copy of an owned String; embedded NUL bytes preserved verbatim.
    The stock element-clone for owned-String containers.
  * `vec_clone [A] v → ( Vec A )` — bitwise shallow copy, trivial element
    types only. `vec_clone_with [A] v ( @ A A ) clone → ( Vec A )` — deep
    copy that runs `clone` per element; use for `Vec[String]`, nested
    `Vec`, `Vec[HashMap]`.
  * `vec_filter_with [A] v ( @ b A ) pred ( @ A A ) clone → ( Vec A )` —
    owned-safe filter: kept elements are *cloned* into the result instead
    of bitwise-aliased, so source and result can both be freed with
    `vec_free_with` without a double-free. Plain `vec_filter` stays the
    fast path for trivial elements.
  * `map_clone [K V] m → ( HashMap K V )` — bitwise, trivial K/V.
    `map_clone_with [K V] m ( @ K K ) clone_k ( @ V V ) clone_v` — deep
    copy. Both preserve the source slot layout verbatim (same cap, probe
    positions, tombstones), so the clone needs no rehash.

  Before this, `vec_filter` / `vec_extend` / `map_keys` / `map_values`
  bitwise-copied elements — silent UB / double-free for any owned element
  type (`Vec[String]`, `HashMap[String _]`, nested containers), an unsafe
  copy the borrow checker cannot see because it happens inside a
  monomorphised generic. The `_with` variants close that hole. Regression
  `compiler/tests/clone_basic.nu` — verified independence (mutate source →
  clone unaffected) and ASan + UBSan + leak-detection clean.

* **`inout` field targets.** An argument of the form `. obj field` at
  an `inout` parameter now passes the *address of that struct field*,
  so the callee mutates exactly that field of the caller's struct in
  place — finer-grained than passing the whole struct `inout`:

  ```
  @ add100 inout i x → v { = x + x 100 }
  : ~ Game g @ Game { @ Counter { 1 99 } 0 }
  ( add100 . g turns )    // g.turns is mutated in place
  ```

  `obj` must be a mutable (`: ~`) struct binding — or an `inout`
  struct parameter, which carries the same backing-pointer shape. The
  field's address is a `getelementptr` resolved through the
  `<sname>__<field>__idx` roster, so plain and generic structs both
  work; the field may itself be a struct (`( bump . g score )`).
  Single-level access (`. obj field`) only. Regression test
  `compiler/tests/inout_field.nu` (+ `should_fail_inout_field_immut.nu`).

* **`inout` / `sink` parameter conventions on generic functions.**
  A generic function may now mark a parameter `inout` (exclusive
  mutable borrow) or `sink` (the callee consumes it), exactly like an
  ordinary function:

  ```
  @ store_g [A] inout i slot  A item → v { = slot + slot 1 }
  ( store_g [i] n 7 )    // n is mutated in place
  ```

  A parameter convention is a property of parameter *position*, not of
  the type arguments, so the `inout` / `sink` index sets are computed
  once from the generic template (the new `compute_generic_inout_sink`,
  keyed by the generic name) and a call site resolves them by that
  name — the mangled-instantiation entry only appears once the
  deferred monomorphisation is compiled, which is too late for the
  call that triggered it. Previously a generic `inout` argument was
  passed by value into a `<T>*` parameter (an LLVM type mismatch). A
  forward call to a generic `inout` function is rejected with the same
  define-before-call diagnostic as the non-generic case. Regression
  tests `compiler/tests/inout_generic.nu` and
  `should_fail_inout_generic_forward.nu`.

* **Forward references for enum-variant payload types.** An enum
  variant whose payload is a struct or enum declared *later* in the
  same file now parses correctly:

  ```
  : | Shape { Dot  Box Geom }   // Geom used before it is declared
  : Geom { i w  i h }
  ```

  Previously the compiler only recognised a payload type already
  registered in the symbol table, so a forward-referenced payload was
  misread as a phantom extra variant — and any `??` match over the
  enum then failed with a bogus non-exhaustive-match error. A new
  linear pre-pass (`scan_type_names`) registers every top-level
  struct / enum / generic-struct name before the main compile pass,
  following `$`-imports. Regression test
  `compiler/tests/forward_enum_payload.nu`.

### Changed

* **`time_parse_iso` now returns `! i ParseErr`** (Unix seconds), not
  `! Time ParseErr`. A Unix timestamp is the more composable parse
  result — directly sortable, comparable and storable — and
  `time_from_unix` reconstructs the broken-down `Time` when its fields
  are needed. The new `time_make` constructor uses the same
  `! i ParseErr` shape for consistency.

### Fixed

* **A side-effecting `~` while-loop condition no longer drops an
  iteration.** `gen_loop` speculatively parsed the condition (to tell a
  while loop from a complement expression used as a statement) and left
  that speculative IR in the output — so the condition was evaluated
  one extra time up front. For a pure condition this was harmless dead
  code; for a side-effecting condition (`~ ( read_next x ) { … }`) the
  first evaluation's side effects happened with no matching body run,
  silently dropping one iteration's work. `gen_loop` now emits the
  condition straight into the loop-check block and only then looks for
  the `{` — the condition is parsed exactly once and evaluated exactly
  (bodies + 1) times; no speculative IR. Regression
  `compiler/tests/loop_cond_sideeffect.nu`.

* **`?? ( call )` on a wide-payload `! T E` result no longer truncates.**
  Matching directly on a function-call expression whose Result payload
  is a wide value struct (a multi-field `Time`-like type) silently
  produced garbage fields: `gen_match`'s heap-box-unboxing
  reconstruction was keyed on `<name>__res_nurl_T`, which only exists
  when the scrutinee is a named binding — so `?? ( f … )` skipped it and
  the `T`-arm binding received the raw heap-box pointer reinterpreted as
  the struct. `gen_match` now synthesises the binding metadata from the
  callee's NURL return type (`__last_nurl_call__`, cleared before the
  scrutinee is evaluated), so the direct-call form reconstructs exactly
  like `?? r`. Narrow payloads (`i`, pointers, handle structs) were
  always fine. Regression `compiler/tests/match_call_wide.nu`.

* **Enum variant with a struct or enum payload now constructs and
  pattern-matches correctly.** Building `@ E { Variant structValue }`
  used to store the struct value straight into the variant's pointer
  slot (an LLVM type error: a multi-field struct is not a pointer),
  and the matching `??` arm mis-unboxed it. Both sites are fixed:
  construction heap-boxes the `%Name` payload (`nurl_alloc` + `store`)
  and the match arm `load`s it back through the slot pointer. Pointer
  payloads (`*Ast`) and single-pointer-handle structs (`String`,
  `Vec`) keep their existing direct-store path. This bug was
  independent of forward references — it affected backward-declared
  payload types too — but went unnoticed because no test constructed
  such a value.

* **`#`-cast from a named aggregate (enum or struct) to an integer
  now works.** `# i someEnumOrStruct` (or any sized integer
  destination) recovers field 0 — an enum's variant tag, or a
  struct's first field. Previously the cast emitted no instruction,
  so the i64-typed use site (a return, `nurl_print_int`, arithmetic)
  failed the LLVM verifier. `gen_cast` now has one unified branch:
  `extractvalue` field 0, normalise it to i64 (`sext` a narrow
  integer field, `ptrtoint` a pointer field, `fptosi` a float
  field), then `trunc` to a narrower destination. A struct whose
  field 0 is itself an aggregate is a hard error. Regression tests
  `compiler/tests/enum_to_int_cast.nu` and
  `compiler/tests/struct_to_int_cast.nu`.

* **Struct construction coerces narrow integer fields.** `@ S { v }`
  where `S`'s field is `i8` / `i16` / `i32` and `v` is a wider value
  (e.g. an i64 literal) used to emit `insertvalue ... i64 …` into the
  narrow field — an LLVM verifier error — forcing an explicit
  `# i8` / `# i16`-cast at every construction site. `gen_agg_lit`
  now coerces each named-struct field value to its declared field
  type: `trunc` into a narrower field, `sext` into a wider one.
  Regression test `compiler/tests/struct_narrow_field.nu`.

### Fixed

* **`mcp_stdio_call` write-failure classification was racy.** Pinging a
  server that had already exited surfaced either `McpStdioEof` or
  `McpStdioIo` depending on whether the write hit `EPIPE` before the
  child's exit was observed — a non-deterministic result (and a flaky
  `mcp_stdio_basic` test). On a failed write `mcp_stdio_call` now
  consults `proc_eof`: if the child's stdout is also at EOF the server
  is simply gone (`McpStdioEof`, matching the write-lands-then-reads-EOF
  path), otherwise it is a genuine transient pipe fault (`McpStdioIo`).
  The dead-server outcome is now deterministic.

## [0.8.0] — 2026-05-20

### Added

* **Native `^^` XOR operator.** Two adjacent carets lex as a single
  `^^` token (the lexer pairs them only when adjacent — `^ ^` with a
  space is still two return tokens). `^^` is a strictly-binary
  operator lowered to LLVM `xor`: bitwise XOR on integer operands,
  logical XOR on `b` operands. Float operands are a compile error
  (LLVM has no float `xor`). Replaces the old `(a | b) - (a & b)`
  identity workaround. `^` alone remains the return operator.
  Grammar (`spec/grammar.ebnf`) and `nurlfmt` updated; regression
  tests `xor_op.nu` + `should_fail_xor_float.nu`.

* **`inout` and `sink` parameter conventions.** `in` / `inout` /
  `sink` are contextual keywords recognised only as a parameter's
  leading token (no lexer change); `in` is the default.
  A parameter marked **`inout`** is an exclusive mutable borrow: the
  callee mutates the caller's binding in place. `inout T` lowers to a
  by-address `<T>*` parameter — the body reads/writes the caller's
  storage with no local copy — replacing the `*T`-parameter and
  return-the-struct mutation idioms. The argument must be a mutable
  (`: ~`) binding; an `inout` function must be defined before it is
  called. Exclusive-access check: a binding passed `inout` must be
  the only argument path to its value at that call — passing it
  again, as a second `inout` or a plain by-value argument, is a
  `warning:`.
  A parameter marked **`sink`** consumes (takes ownership of) its
  argument: it lowers to an ordinary by-value parameter, and the
  borrow checker records the argument binding as moved so a later
  use is a use-after-move. `sink` v1 applies to `Vec` and other
  manually-managed handles; passing a compiler-auto-dropped value
  (owned string / slice / `Drop` value / struct with owned fields)
  to a `sink` parameter is rejected pending drop-ownership transfer.

* **Static borrow checker, on by default.** A diagnostic analysis
  pass (disable with `--no-borrowck`) that never changes generated
  code — a
  borrow-clean program compiles to byte-identical IR. Closes four
  bug classes with `warning:` diagnostics: use-after-move (a binding
  read after its ownership moved), alias double-free (`: T b a` of an
  owned heap value moves `a`), stack-reference escape (a closure
  capturing a `: ~`-mutable struct by pointer that is returned,
  pushed into a container, spawned onto a thread, or assigned into a
  longer-lived binding — a region-based check), and iterator
  invalidation (mutating a container — `vec_push`/`vec_free`/… — from
  inside a `~`-foreach that iterates it). Ownership + borrow rules
  documented in the new [`docs/MEMORY.md`](docs/MEMORY.md).

* **Tail-call optimisation in the @-fn dispatch path.** `gen_ret`
  now flags the upcoming return-value expression as
  tail-position; `gen_call` snapshots + clears the flag on entry,
  so only the outermost call in the return expression is treated
  as tail (argument-evaluation recursions stay non-tail). In the
  regular @-fn dispatch path the LLVM `call` becomes `tail call`
  when (a) the flag was set, (b) `rlt == fn_ret_ty` so LLVM
  accepts the marker, (c) the callee is not variadic, and (d)
  `gen_ret` saw no pending owned-string / owned-slice / owned-
  struct-field / user-drop / defer in scope at flag-set time
  (any of those would emit drop calls between the tail call and
  `ret`, which LLVM would silently demote).

  Deliberately chose `tail` over `musttail`: `tail` is a hint
  LLVM may drop when its safety analysis can't confirm the
  rewrite (alloca-escape through an arg, etc.), so a
  misclassification only costs an optimisation. `musttail` is
  verifier-enforced and would fail on NURL's owning ABI where
  the same source-level signature lowers to different LLVM
  types across call sites.

  Effect: tail-recursive functions no longer blow the stack —
  `compiler/tests/tco_deep_recursion.nu` runs a 5_000_000-deep
  countdown in O(1) stack (~7 ms wall-clock). Trait/impl,
  closure-loaded var, and fn-pointer-parameter dispatch paths
  intentionally still emit a plain `call` (different shapes; not
  the deep-recursion targets TCO exists for).

  Coexists with `--g` DWARF emission: `tools/dwarf_test.sh` still
  passes all five phases.

* **DWARF Phase 6 composite-type rendering.** User structs and
  generic-instantiation handles (`%Vec__u8`, `%String`, `%FmtTok`,
  user `% Point`, …) now resolve under `nurlc --g` to a
  `!DICompositeType(tag: DW_TAG_structure_type, …)` carrying one
  `!DIDerivedType(tag: DW_TAG_member, …)` per field — instead of
  the previous i64 placeholder. `gdb ptype Point` lists the fields
  with their NURL names + base types; `print p` renders the value
  as `{x = 3, y = 7}`; `print p.x` evaluates a single field.

  Field roster lives in the existing symbol table next to the
  per-field `__idx_N__type` entries — `gen_struct_decl` and the
  generic-instantiation emitter now also record
  `<sname>__field_count` and `<sname>__idx_N__name`. New helpers
  `dbg_size_bits` / `dbg_align_bits` / `dbg_align_up` compute
  LLVM-natural cumulative field offsets so the emitted
  `!DIDerivedType` member offsets match the actual layout
  clang/LLVM uses. Self-referential structs (a cell holding a
  pointer to itself, etc.) are safe — the composite id is interned
  in `g_dbg_type_syms` before the per-field recursion descends
  through `dbg_type_id_for`, so a back-edge returns the cached id
  instead of looping.

  Regression: `compiler/tests/dwarf_struct.nu` exercises the
  codegen path in the standard test corpus; `tools/dwarf_test.sh`
  picks up a fifth phase that drives gdb in batch mode to assert
  `ptype` + `print` + field-access over the new test. Bootstrap
  fixed point holds — non-debug IR is byte-identical.

  Per-instantiation source-line precision for generics remains
  deferred.

## [0.7.2] — 2026-05-19

### Added

* **Serde-style `JsonSerialize` trait + decoder helpers
  (`stdlib/ext/serde.nu`).** A NURL trait `JsonSerialize [T] { @ to_json
  T x → Json }` with first-arg dispatch and impls for `i` / `b` /
  `f` / `s` / `String`, paired with per-type `from_json_<T>` helpers
  (`from_json_i` / `_b` / `_f` / `_string` / `_str_borrow`) that
  return `!T ParseErr`. User types add their own `% JsonSerialize
  MyStruct { @ to_json MyStruct x → Json { ... } }` impl and a
  hand-written `mystruct_from_json`. The shape mirrors Serde:
  format-specific traits (JsonSerialize stands alone today; TOML /
  MsgPack get their own trait when those formats land) and a
  Deserialize-by-naming-convention because NURL's first-arg-dispatch
  cannot carry a trait whose receiver is `Json` — every impl would
  collide. Demo: `examples/serde_demo.nu` round-trips a `Point`
  through JSON text. Regression: `compiler/tests/serde_basic.nu`.

* **docs/GOTCHAS.md folded back into the compiler + grammar +
  README — empty stub now.** The historical "gotchas" list existed
  to compensate for compile errors that lacked enough context to
  fix the source. As of v0.7.1+ that gap is closed: every old item
  now surfaces as a `file:line:col:` `error:` / `warning:` with a
  pointing caret + concrete cure inline (see "Source-level compiler
  diagnostics" below for the seven new emit sites + the four shipped
  prior). The residual edges — prefix-arity strictness, `^` not
  being XOR — are grammar properties, not surprises; they live in
  README's Known Limitations → Grammar table next to the existing
  imports / FFI limitations, and grammar.ebnf's `bin_expr` /
  `ret_expr` productions now carry explanatory comments. The
  GOTCHAS.md file is preserved as a redirect stub so external
  links (and the MCP `nurl_read_gotchas` resource) keep working,
  but new code should not add items there — extend the compiler
  diagnostics or the grammar comments instead.

* **Two more compiler diagnostics on top of the prior five.**
  Bare `@-fn` used as a closure value (`error:` at the use site
  with the `\ args → R { ( fn args ) }` wrap), and the
  `? cond bare-then bare-else { … } { … }` shape (`warning:` —
  the n-ary `&`/`|` foot-gun where `&` only consumed 2 of the
  operands and the `{ … }` blocks became side-effect statements).
  Both ride on the same `die`/`warn` infrastructure; verified via
  the `bare '@-fn'` / `?-with-{` smoke programs.

* **Source-level compiler diagnostics for five language gotchas.**
  Previously each surfaced as either silent UB or a cryptic LLVM /
  arity error far from the source. Each now emits a
  `file:line:col` diagnostic with a caret + the concrete cure, and
  is mirrored in `docs/GOTCHAS.md` items 6-10 (the Quick-reference
  table gained an "Auto-diagnosed?" column).
    * `^ ?? value { ... }` with `^`-arms — `error:` augments the
      existing `return expression has no value` message with the
      `: ~ T rc init / ?? { … = rc v } / ^ rc` refactor (item 6).
    * `nurl_str_len` (libc, expects `s`) called on a `%String`,
      and `string_len` (stdlib, expects `%String`) called on a
      raw `i8*` — both `error:` at the call site (item 7).
    * Parameter named `entry` — `error:` at the param parse,
      naming the LLVM `entry:` block-label collision (item 8).
    * `# T { ... }` where T is a registered struct/enum — `error:`
      at the cast site suggesting `@ T { ... }` (item 9).
    * `: ~ *T` mutable pointer bindings — `warning:` at the decl
      pointing at the long-loop miscompile (item 10). Warn rather
      than die because trivial isolated cases work; the advisory
      catches the hoist patterns that crash deterministically
      ~tens of thousands of iterations in.

* **One-command developer install (`./install.sh`).** Bootstraps the
  compiler (skipped if `build/nurlc` already exists), builds
  `nurl-lsp`, symlinks it into `~/.local/bin/nurl-lsp` so VS Code /
  Cursor / Windsurf find it without any settings tweak, packages
  the VS Code extension (`vsce package`) and installs it via the
  editor's CLI when one is on PATH. Idempotent: re-run any time to
  pick up a newer checkout. Flags: `--no-vscode`, `--no-path`,
  `--force`, `--uninstall`, `--help`.

### Changed

* **`tooling/vscode-nurl` bumped 0.3.0 → 0.4.4** (matches the
  `nurl-lsp` server version it pairs with). README rewritten to
  document the actual feature set — go-to-definition (single +
  cross-file via `$ `path`` imports), hover, document outline,
  workspace-wide IDENT completion, `Ctrl-T` symbol search, folding
  ranges, and `nurlfmt`-backed formatting — replacing the stale
  "coming in later iterations" line that misrepresented an
  already-shipped server. New packaged extension:
  `tooling/vscode-nurl/nurl-0.4.4.vsix`.

## [0.7.1] — 2026-05-19

### Changed

* **MCP `protocolVersion` bumped from `2024-11-05` to `2025-11-25`
  (current stable revision)** + centralized + drift-check tooling.
  All seven hardcoded pinnings across `stdlib/ext/mcp.nu`,
  `mcp_registry.nu`, `mcp_client.nu`, `mcp_stdio.nu` now route
  through a single `mcp_protocol_version → s` helper. A companion
  `mcp_protocol_version_legacy → s` returns `2024-11-05` for
  callers that need to explicitly negotiate the older shape
  (server MAY agree to whatever the client requests as long as
  it's a revision the server supports).

  MCP revisions only bump on backwards-incompatible changes per
  the spec's versioning page, so a server advertising the latest
  revision serves earlier clients fine — pinning to an old date
  pushes negotiation the wrong way.

  New helper: `tools/mcp_spec_drift_check.sh` fetches the spec
  site's versioning page, parses the current revision, compares
  to NURL's pinned value, exits 1 on drift with a pointer at the
  changelog URL. Drop-in for CI or a weekly cron.

### Added

* **DWARF debug-info support (compiler + driver).** `nurlc --g
  foo.nu` now emits LLVM `!DICompileUnit` /
  `!DIFile` / per-fn `!DISubprogram` / per-stmt `!DILocation` /
  per-`:`-binding `!DILocalVariable` + `llvm.dbg.declare` metadata.
  `nurl.sh --debug foo.nu` forwards `--g`, drops `-flto` (which
  silently strips DWARF in the current LLVM/gcc-ld pipeline), and
  side-by-side rebuilds `stdlib/runtime_debug.o` with `-g` so the
  link preserves `.debug_info` end-to-end. `gdb` then resolves
  `break fizzbuzz`, `break foo.nu:42`, `print x`, `whatis x` (with
  NURL type names — `i`/`u8`/`b`/`f`/`s`/...), and `backtrace` with
  source file + line for every NURL frame. Closures and generic
  monomorphisations get their own subprograms with mangled names.
  `nurl_panic` now dumps a stack trace via libc's `backtrace_*` API
  before aborting; pipe each frame's offset through `addr2line -e
  <binary>` to recover `.nu:LINE`. End-to-end regression:
  `./tools/dwarf_test.sh` (gracefully skipped if `gdb` is absent).
  Composite-type rendering (`!DICompositeType` for `%Vec` /
  user structs) and per-instantiation source-line precision for
  generics are not currently implemented.

* **Compiler: closure-escape warnings for `vec_push` / `vec_insert` /
  `vec_set` / `thread_spawn`.** Extends the existing 2026-05-15
  `^`-return escape check (`gen_ret` reading `__last_closure_byref__`
  + `<name>__captures_byref`) to four more sites where a closure
  takes ownership across a scope boundary. `gen_call` snapshots
  `__last_ident_name__` per-argument; when the callee's `fname` is
  one of the four AND the argument names a binding tagged
  `__captures_byref = 1`, emits a soft `warning:` line consistent
  with the existing escape diagnostic. By-name only — struct-wrapping
  (`@ Slot { cb }` then push the slot) passes through silently, which
  is acceptable: we catch the obvious one-line foot-gun rather than
  every conceivable indirection. Closes gotcha #8 to the same scope
  as #5. Regression: `compiler/tests/should_warn_closure_escape_vec.nu`
  (positive `thread_spawn` + 2 negative controls).

  `docs/GOTCHAS.md` §5 updated to document the extended coverage;
  the `vec_push [(@ v)]` form remains untested because anonymous
  closure types aren't yet accepted as generic-arg type names — a
  separate `parse_type_paren` extension would unlock it.

* **MCP server framework with closure-based registry.**
  `stdlib/ext/mcp_registry.nu` (~550 LOC) replaces the previous
  "write your own JSON-RPC dispatch loop" workflow with a uniform
  `register-tool-with-handler` API. The Channel[A] generic-propagation
  fix (2026-05-17) unlocked closure-in-Vec storage, which is what
  makes this possible.

  Three first-class entity types:
    - `McpTool { name, description, input_schema, ( @ Json Json ) handler }`
    - `McpPrompt { name, description, arguments_schema, ( @ Json Json ) handler }`
    - `McpResource { uri, name, mime_type, description, ( @ Json ) handler }`

  Surface:
    - `mcp_registry_new name version → McpRegistry`
    - `mcp_registry_add_tool / _add_prompt / _add_resource` —
      register entities with closure handlers.
    - `mcp_registry_dispatch r method ?params → Json` — single entry
      point routing JSON-RPC method names through the per-method
      dispatchers. Covers `initialize`, `tools/list`, `tools/call`,
      `prompts/list`, `prompts/get`, `resources/list`,
      `resources/read`, `ping`. Unknown methods return an
      `{__error__: "method not found"}` envelope.
    - `mcp_registry_envelope r req → ?Json` — transport-agnostic
      single-request adapter. Notifications (no `id`) return None.

  Transports:
    - **stdio server** — `mcp_serve_stdio r → ! v McpServeErr`
      reads JSON-RPC frames off stdin (line-delimited per spec),
      dispatches via the registry, writes responses to stdout. NURL
      is now a complete bidirectional MCP party (server-side stdio
      pairs with the existing client-side stdio from `mcp_stdio.nu`).
    - **HTTP adapter** —
      `mcp_http_dispatch_for_registry r → ( @ ? Json Json )` returns
      a closure that plugs straight into the existing
      `mcp_http_handler` from `stdlib/ext/mcp_http.nu` (batch
      requests + CORS + session-id echo + SSE stub already covered
      there).
    - **Bearer-auth middleware** —
      `mcp_http_with_bearer_auth handler expected_token` decorates
      any HTTP handler with `Authorization: Bearer <token>`
      enforcement. Missing or mismatched → 401 with
      `WWW-Authenticate: Bearer realm="mcp"`.

  Spec out-of-scope for v1 (tracked):
    * `resources/subscribe` + change notifications (needs an SSE
      push channel from a custom accept loop).
    * `completion/complete` (rarely-used spec feature).
    * `sampling/createMessage` (server→client reverse RPC).

  Regression: `compiler/tests/mcp_registry.nu` exercises every
  dispatch path including 2 tool invocations (echo + add(17,25)=42),
  prompt rendering with arguments, resource read, unknown-method
  error envelope, and ping.

* **`json_as_str` / `json_as_int` / `json_as_bool` accessors** in
  `stdlib/ext/json.nu`. Convenience extractors for the leaf-typed
  variants of `Json`, returning the unwrapped value (or empty/zero
  for the wrong variant). `json_as_str` returns a BORROWED view
  into the underlying JStr's String backing buffer — copy via
  `string_from` for longer-lived references.

* **DoS connection caps for the HTTP server.** Two-axis protection
  against connection-exhaustion attacks:
    - `DosLimits { max_concurrent_conns, max_conns_per_ip }` declares
      the caps. `dos_default_limits → DosLimits { 1024 16 }` covers
      the typical single-VM-public-HTTPS shape; CG-NAT'd clients
      (10s of users behind one public IP) stay under 16 in real usage.
    - `server_new_with_dos listener handler limits` constructs an
      HttpServer with a runtime-side `NurlDosState` (mutex-protected
      counter + linear per-IP table, up to 256 distinct active IPs).
    - At accept time, `server_run_once` calls
      `nurl_dos_state_try_acquire`. Over-cap conns are closed
      immediately at the TCP layer (no canned 503 response — cheapest
      possible rejection, keeps the server's per-cap cost low).
    - Per-connection cleanup releases the counter on conn end;
      multi-worker pools (`server_run_pool`) share the same state via
      the shared HttpServer handle.
    - `server_active_conn_count` exposes the live counter for
      `/metrics`-style observability endpoints.

  Runtime additions in `runtime.c` §23: `NurlDosState` struct + four
  public entry points (`nurl_dos_state_new` / `_try_acquire` /
  `_release` / `_free`) + `_active` accessor. Cross-platform mutex
  (`pthread_mutex_t` POSIX, `CRITICAL_SECTION` Win32). Linear scan
  with O(1) last-element-swap eviction on count→0 keeps the IP
  table compact under steady churn.

  Verified live (NURL_NET_TESTS=1):
  `compiler/tests/http_server_dos.nu` opens 4 concurrent TCP conns
  from 127.0.0.1 against a server with `max_per_ip=2`; the first
  two complete the handshake + handler, the last two are rejected
  pre-handshake → 2 accepted + 2 rejected.

* **TLS extras: SNI + live cert reload + mTLS.** Three additions
  that close the critical-path tuotantopuutteet in the TLS stack
  built on top of the existing `tcp_listen_tls` listener — the new
  operations attach to an
  already-created listener and take effect on subsequent handshakes.

    - `tcp_tls_add_sni listener hostname cert_path key_path → !v NetErr`
      Registers a per-virtual-host cert/key against the listener
      using OpenSSL's `SSL_CTX_set_tlsext_servername_callback`.
      Clients that offer no SNI extension OR offer an unknown
      hostname fall through to the default cert (set at listen
      time) — matches RFC 6066 §3 server semantics. Idempotent
      on re-add (replaces the stored pair for an existing host).
      Required for multi-tenant HTTPS where one listener serves
      multiple virtual hosts.

    - `tcp_tls_reload listener ?hostname cert_path key_path → !v NetErr`
      Atomically swaps the listener's default SSL_CTX (empty
      hostname) OR a matching SNI entry's SSL_CTX with one built
      from the new cert/key files. Per-listener mutex serialises
      the swap against the concurrent accept loop; OpenSSL refcounts
      the old SSL_CTX so in-flight conns that already wrapped an
      SSL handle from it stay valid until they close. Natural
      shape for Let's Encrypt cert rotation triggered from SIGHUP
      or a control endpoint.

    - `tcp_tls_require_client_cert listener ca_bundle_path b strict → !v NetErr`
      Sets `SSL_VERIFY_PEER` on the listener; when `strict` is true,
      adds `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` so the handshake fails
      outright for unauthenticated clients (mTLS-mandatory).
      `tcp_peer_cert_subject TcpConn → String` reads the peer's
      X509 DN in OpenSSL one-line format (e.g.
      "/CN=test-client/O=NURL/C=FI") for the application's
      authorisation decisions.

  Verified live (NURL_NET_TESTS=1):
  `compiler/tests/http_server_tls_extras.nu` runs three sections —
  SNI hostname dispatch (api.example.com → CN=api cert,
  www.example.com → CN=www cert, unknown.example.com → fallback to
  CN=localhost default), live reload (CN=localhost → swap →
  CN=reloaded.example.com), and mTLS (no client cert → rejected,
  valid client cert → 200 OK). All probes driven via `openssl
  s_client` shell-outs.

  Runtime additions in `runtime.c` §18: `NurlTcp` grew
  `sni_entries` + `sni_count` + `sni_cap` + a per-listener
  cross-platform mutex (`pthread_mutex_t` on POSIX,
  `CRITICAL_SECTION` on Windows). Four new C entry points
  (`nurl_tcp_tls_add_sni`, `nurl_tcp_tls_reload`,
  `nurl_tcp_tls_require_client_cert`, `nurl_tcp_peer_cert_subject`).
  `tcp_close` extended to free the SNI registry + destroy the
  mutex; in-flight SSL_CTX refs are released via SSL_CTX_free's
  refcount decrement, so cleanup is safe under concurrent shutdown.

## [0.7.0] — 2026-05-18

Full HTTP/2 server stack (RFC 9113 + RFC 7541) alongside WebSocket
(RFC 6455), gzip wire format (RFC 1952), and an AddressSanitizer +
UndefinedBehaviorSanitizer quality gate.
Three compiler fixes (single-pointer-handle Result coercion, `?u`
match-arm unsigned propagation, `gen_assign` last-type publishing) +
one new language feature (integer-literal match arms) round out the
release. Bootstrap fixed point holds; 0 SAN_FAIL across the 208-test
sanitized corpus.

### Added

* **HTTP/2 server-side (RFC 9113 + RFC 7541).** Four pure-NURL modules
  plus one runtime extension for ALPN. Same `( @ HttpResponse HttpRequest )`
  handler contract as HTTP/1.1 — application code unchanged.

  Modules:
    - `stdlib/ext/http2_frame.nu` (~360 LOC) — binary framing: 9-byte
      header + all 10 frame types + connection preface validation +
      pure round-trip helpers + socket I/O + one-shot senders for
      SETTINGS / PING / GOAWAY / WINDOW_UPDATE / RST_STREAM.
    - `stdlib/ext/http2_hpack.nu` (~900 LOC) — RFC 7541 header
      compression: 61-entry static table + dynamic table with FIFO +
      size-based eviction + N-bit prefix integer codec + string codec
      (literal or Huffman) + all 6 header-field representations +
      complete Huffman decoder covering all 257 Appendix B codes
      across 21 length buckets (5..30 bits).
    - `stdlib/ext/http2_conn.nu` (~770 LOC) — connection + stream
      state machine: SETTINGS exchange + apply, stream state diagram
      per RFC 9113 §5.1 (idle → open → half-closed → closed),
      HEADERS+CONTINUATION assembly with §6.10 interleaving check,
      DATA flow control with connection-level WINDOW_UPDATE
      replenishment, PING/GOAWAY/RST_STREAM dispatch, request
      assembly from HTTP/2 pseudo-headers (:method/:path/:scheme/:authority)
      to the existing HttpRequest shape, response emission with §8.2.2
      hop-by-hop header stripping.
    - `stdlib/ext/http2_server.nu` (~100 LOC) — `http2_serve` +
      `server_run_h2_capable`. The latter accepts a connection,
      checks ALPN selection via `tcp_alpn_protocol`, and routes to
      h2 OR the existing HTTP/1.1 keep-alive loop transparently.

  Runtime extension:
    - `nurl_tcp_listen_tls_alpn(host, port, backlog, cert, key,
      "h2 http/1.1")` — wraps `SSL_CTX_set_alpn_select_cb` over the
      existing TLS listener. Wire-format packing of the server's
      preference list happens C-side. NurlTcp handle gained
      `alpn_wire` + `alpn_wire_len` fields.
    - `nurl_tcp_alpn_selected(handle)` — reads
      `SSL_get0_alpn_selected` post-handshake, returns heap-owned
      NUL-terminated string ("h2" / "http/1.1" / "").
    - NURL surface: `tcp_listen_tls_with_alpn` + `tcp_alpn_protocol`
      in `std/net.nu`.

  v1 scope intentionally excludes:
    * Client-side h2 (symmetric to server; ship when a consumer asks).
    * h2c (HTTP/1.1 → h2 cleartext upgrade — TLS+ALPN is the
      universal modern shape).
    * PUSH_PROMISE / server push (deprecated by RFC 9113 §8.4).
    * PRIORITY frames (obsoleted by RFC 9218 — default ordering OK).

  Verified offline against RFC 9113 §4 framing vectors and
  RFC 7541 Appendix C / C.4.1 HPACK + Huffman vectors via
  `compiler/tests/http2_basic.nu`. Bootstrap fixed point holds.
  ASan + UBSan: 0 SAN_FAIL across the 208-test corpus.

  Usage:
  ```
  : !TcpListener NetErr ll
    ( tcp_listen_tls_with_alpn `127.0.0.1` 8443 16
                               `cert.pem` `key.pem`
                               `h2 http/1.1` )
  ?? ll {
      T listener → {
          : HttpServer s ( server_new listener my_handler )
          ( server_run_h2_capable s )
      }
      ...
  }
  ```

* **Compiler: integer-literal match arms.** `?? value { 1 → ... 42 → ... -1 → ... _ → ... }`
  is now valid wherever `value` has an integer LLVM type (i / i8/16/32/64,
  u/u16/u32/u64). Each arm emits a single `icmp eq <match_type>` and
  branches; the wildcard `_` arm catches the residual (required —
  exhaustiveness is not statically checked across the full integer
  domain). Skips the enum-variant lookup, payload-binding, and
  duplicate-arm tracking paths that named-variant arms exercise.
  `stdlib/ext/http2_hpack.nu`'s 280+ line `? == x N { ^ Y } {}`
  cascade for the HPACK static table + Huffman per-length lookup
  tables was rewritten on top of this and is significantly more
  readable. Regression: `compiler/tests/match_int_literal.nu`.

* **AddressSanitizer + UndefinedBehaviorSanitizer quality gate.** Two
  manual entry points:
    - `./build.sh --san` rebuilds the runtime + every bootstrap stage
      with `-fsanitize=address,undefined -fsanitize-address-use-after-scope
      -fno-omit-frame-pointer -fno-sanitize-recover=all`. LTO is
      dropped because clang's LTO+sanitizer combo produces opaque
      link-time errors on NURL's cross-module function pointers (the
      runtime/user-code inline win isn't the point of a san run).
      LeakSanitizer is disabled during the bootstrap itself
      (`ASAN_OPTIONS=detect_leaks=0`) because nurlc_py/nurlc_self
      intentionally don't free their process-lifetime str-pool /
      sym-arena globals at exit.
    - `compiler/tests/run_san_tests.sh` runs the full .nu corpus
      under the sanitized runtime, captures stdout / stderr per-test
      separately, scans stderr for ASan/UBSan/LeakSanitizer markers,
      and reports `PASS` / `SAN_FAIL` / `COMPILE_FAIL` / `LINK_FAIL`.
      Non-zero exit codes without sanitizer markers count as PASS
      (several tests in the corpus deliberately return computed values
      as exit codes — `native_sum` returns 55, `test_immutable_assign_error`
      aborts to prove the runtime check fires, etc.). Skips
      `should_fail_*` compile-negatives and helper modules without
      `main()`. Leak detection is opt-in via `LSAN_DETECT_LEAKS=1`.

  First sweep result: 188 PASS, 0 SAN_FAIL across 206 tests. The
  infrastructure stays manual — invoke when validating a release
  candidate or triaging a memory-shape bug, not on every build.

* **WebSocket server-side (RFC 6455).** `stdlib/ext/websocket.nu`
  (~570 LOC pure NURL). Composes on the HTTP/1.1 stack: client sends
  `Upgrade: websocket` + `Sec-WebSocket-Key` + `Sec-WebSocket-Version: 13`,
  server validates via `ws_perform_handshake[_with]` and writes the
  `101 Switching Protocols` response, both sides switch to the binary
  frame protocol over the SAME `TcpConn`. TLS works transparently —
  `wss://` routes through `tcp_listen_tls` + the polymorphic `TcpConn`
  SSL dispatch with zero additional code in this module.

  **Surface:**
    - Handshake: `ws_is_upgrade`, `ws_accept_key`,
      `ws_handshake_response_for`, `ws_perform_handshake[_with]`
      (`_with` accepts an optional subprotocol echo).
    - Low-level frame I/O: `ws_serialize_frame` (pure, testable builder),
      `ws_read_frame`, `ws_write_frame`.
    - Convenience writers (server-side, never masked per RFC §5.1):
      `ws_send_text`, `ws_send_binary`, `ws_send_ping`, `ws_send_pong`,
      `ws_send_close i code s reason`.
    - Message reader: `ws_read_message` assembles continuation frames
      per RFC §5.4, auto-pongs incoming pings, surfaces peer close as
      `WsClosedByPeer`. Text payloads validated UTF-8 before return.
    - Serve loop: `ws_serve_messages` reads messages, dispatches to a
      `( @ ! v WsErr WsMessage )` handler, performs the full close
      handshake on exit (mapping errors to RFC §7.4 close codes:
      `WsInvalidUtf8 → 1007`, `WsProtocol*  → 1002`, `WsMessageTooLarge → 1009`,
      everything else `→ 1011`).
    - `WsLimits { max_frame_bytes, max_message_bytes, read_timeout_ms,
      fragment_max_count }`; defaults are 16 MiB / 64 MiB / 60 s / 128.
    - `ws_validate_utf8` (RFC 3629 strict) is exposed publicly — useful
      outside the WebSocket context too.

  **Validation rigour:** RSV1–3 bits must be 0 → `WsProtocolReservedBit`;
  opcode must be in {0,1,2,8,9,10} → `WsProtocolBadOpcode`; control frames
  MUST have FIN=1 (`WsProtocolControlFragmented`) and payload ≤125 B
  (`WsProtocolControlTooLarge`); client→server frames MUST be masked
  (`WsProtocolUnmasked`); text payloads MUST be valid UTF-8 — overlongs,
  UTF-16 surrogates (U+D800-U+DFFF), and codepoints above U+10FFFF all
  rejected; close codes constrained to 1000–4999; the fragment-count
  cap defends against a ping-flood interleaved with continuation frames.

  **Verified against RFC 6455 vectors:**
    - §1.3 accept-key worked example
      (`dGhlIHNhbXBsZSBub25jZQ==` → `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`).
    - §5.7 unmasked text frame `"Hello"` round-trips to
      `81 05 48 65 6c 6c 6f`.
    - Length-encoding transitions: 126-byte payload triggers the 16-bit
      extended-length header; 65536-byte triggers the 64-bit form
      (with the spec-required MSB-clear check on the top byte).

  Regression: `compiler/tests/websocket_basic.nu` (6 sections, 30
  assertions). v1 scope is server-side only — a symmetric client-side
  API is tracked for follow-on work if a real consumer asks. No
  `permessage-deflate` extension; subprotocol header echo is the only
  negotiation surface.

* **SHA-1 in runtime §17** (RFC 3174 self-contained, ~80 LOC). Added to
  enable the WebSocket handshake's `Sec-WebSocket-Accept` derivation;
  exposed via new `sha1_bytes` (length-aware, binary-safe → 20 raw
  bytes) and `sha1_hex` (→ 40-char lowercase) in `stdlib/std/hash.nu`.
  SHA-1 is documented as protocol-compatibility-only — not recommended
  for new security-sensitive code; use `sha256_hex` for that.

* **`stdlib/ext/http_full.nu`** now imports `ext/websocket.nu` so one
  `$`-include brings the full HTTP stack including WebSockets in scope.

### Fixed

* **`signal_basic.nu` — F-arm pattern no longer binds the undef
  Option payload.** The previous `F e → { ( string_free e ) ... }`
  shape passed the F-tag's undef String handle to `string_free`,
  which deep-dispatched into `nurl_peek(NULL, 0)` and tripped UBSan's
  "applying zero offset to null pointer". Replaced with bare `F → ...`
  (Option's None arm carries no data). Surfaced by the first sanitized
  run of the corpus and was a silent crash even outside of ASan
  (`EXIT 139` / `dumped core` in the baseline — now `EXIT 0` cleanly).

* **`stdlib/runtime.c` `nurl_peek` / `nurl_poke` defensively handle
  NULL base.** `nurl_peek` returns 0 instead of dereferencing;
  `nurl_poke` silently no-ops. Safety net for the same caller-side
  mistake the `signal_basic` fix patched at source — a future stdlib
  binding that hands an Option-F-arm payload to a vec-style API will
  log a soft warning under ASan/UBSan but not crash the process.

* **Compiler: `?u → T b →` match-arm now propagates the unsigned flag
  to the payload binding.** `parse_type_opt` stashes the inner-T NURL
  token in `__last_opt_nurl_t__`; `gen_let_or_struct` copies it to
  `<name>__opt_nurl_T`; `gen_match`'s T-arm payload binding tags
  `<pv0>__unsigned = 1` when the inner T is `u` / `u16` / `u32` / `u64`.
  Without this fix the alloca dropped the unsigned-ness and a
  downstream `# i b` cast in the arm body emitted `sext` instead of
  `zext` for high-bit-set bytes, surfacing as wrong hex nibbles in
  `bytes_to_hex` over SHA-1 / SHA-256 digests. `bytes_to_hex` reverted
  from its temporary direct-pointer workaround back to the natural
  `vec_get [u]` + match-arm path.

* **Compiler: `! (Vec u) E` Ok-arm now coerces the i64 payload to the
  `{ ptr }`-shaped single-handle struct.** Two-part fix:
  `parse_type_res` stashes `__last_res_t_llvm__` (LLVM type of T) so
  `gen_let_or_struct` can store `<name>__res_t_llvm` for paren-compound
  T like `( Vec u )` whose NURL-source name is just `(`;
  `gen_match`'s reconstruction path uses it as a fallback after the
  NURL-name lookup fails. Additionally, `coerce_store_val` gained an
  `i64 → single-pointer-handle-struct` case (one-field struct whose
  field 0 is a pointer — covers `Vec[A]`, `String`, `Channel[A]`,
  `Thread`, `Arena`) that wraps via `inttoptr` + `insertvalue` at
  field 0. Without these, `?? r { T pb → @ Frame { … pb } }` over
  `! ( Vec u ) E` generated invalid IR (`insertvalue %Frame, i64`)
  forcing callers into `vec_with_cap + vec_extend` copy workarounds.
  `ws_read_frame` reverted from the copy workaround back to the
  direct payload pass-through.

* **Compiler: `gen_assign` now publishes the LHS type via
  `nurl_set_last_type`.** Without this, an `=`-assignment as the last
  expression of a match arm (`F e → { = err e }`) reported the
  RHS-expression's pre-coerce type to the surrounding `gen_match`,
  causing the phi to be typed for the RHS while the actual stored
  register held the coerced LHS type. LLVM verifier rejected the
  mismatch. Surfaced in `ws_read_frame`'s `?? hdr_r { T … F e → { = err e } }`
  which previously needed a trailing `( nurl_print `` )` to push the
  arm's last-expression type back to void; that workaround removed.

* **Gzip wire format (RFC 1952).** `stdlib/ext/compress.nu` gains
  `gzip_compress` / `gzip_compress_at level` / `gzip_decompress` —
  byte-identical interop with the `gzip` / `gunzip` CLI tools and HTTP
  `Content-Encoding: gzip`. Magic + 10-byte header, raw deflate body,
  CRC-32 + ISIZE trailer, all per RFC 1952. Decompress auto-detects
  gzip OR zlib wire format on the input side (libz's
  `inflateInit2_(windowBits=15+32)`), so a single helper handles both
  shapes coming back from heterogeneous peers. Decompress also reads
  the ISIZE trailer to pre-size the output buffer, avoiding the
  grow-and-retry loop on the common path (sub-4 GB inputs).
  Errors map to the existing `CompressErr` enum
  (`CompressData` / `CompressMemory` / `CompressBufTooSmall` /
  `CompressOther`). Empty input passes through to an empty `Vec[u]`
  with no magic-byte production, matching the zlib/zstd shape.
  Regression: `compiler/tests/compress_gzip.nu` (round-trip + magic
  bytes 0x1f 0x8b 0x08 + level-0 store-only + empty + auto-detect
  zlib + garbage rejection).

* **`runtime.c` §22 — gzip bridge.** `nurl_gzip_compress` /
  `nurl_gzip_decompress` wrap libz's streaming
  `deflateInit2_(windowBits=15+16)` / `inflateInit2_(windowBits=15+32)`
  + `deflate(Z_FINISH)` / `inflate(Z_FINISH)` + matching `End`. ABI
  mirrors `compress2` / `uncompress` (in/out `dst_len`, return 0 on
  success or libz error code on failure; sentinel `-98` when the build
  lacked zlib). The C-side bridge stays because `z_stream`'s sizeof
  and field layout are platform-specific (88 B on Win64 LLP64, 112 B
  on Linux/macOS x64 LP64), and `deflateInit2_` checks an exact-sizeof
  match — mirroring the struct from NURL would be brittle across
  toolchains. Same architectural pattern as the sqlite3 borrowed-view
  bridge: thin, ABI-faithful, no state caching beyond what libz needs.

### Changed

* **`stdlib/ext/compress.nu` header comment** updated: the
  zlib-vs-gzip wire-format gap section now documents the gzip helpers
  shipped alongside, with a pointer to `runtime.c` §22 for the bridge
  rationale.

* **`build.sh`** zlib detection now sets
  `ZLIB_CFLAGS="-DNURL_HAVE_ZLIB ..."` and threads it into the runtime
  compile step so the §22 bridge compiles in when zlib1g-dev is
  present. Without zlib, `nurl_gzip_*` short-circuit to the
  `NURL_GZIP_ERR_UNSUPPORTED` sentinel which the NURL surface maps to
  `CompressOther` — graceful runtime degradation rather than a link
  error.

### Fixed

* **Stale "Quoted CSV Support" roadmap entry closed.** `stdlib/ext/csv.nu`
  has implemented RFC 4180 quoting via the `CSVDialect { delimiter,
  crlf, quote_char }` struct (and the matching `CSVTable` arena's
  `escape_buf`) since the v2 arena rewrite. The roadmap line was a
  leftover from the pre-arena CSV prototype; surfaced and removed
  during the critic-cleanup sweep.

## [0.6.1] - 2026-05-17

### Added

* **Generic propagation through nested structs.** Two generic structs
  side-by-side compose freely: a generic function that returns
  `( Outer A )` while internally allocating `*( Inner A )` and writing
  its fields now compiles, and a generic struct whose field types
  reference another generic (e.g. `Wrap[A] { ( Vec A ) items, … }`)
  emits its inner instantiation before the outer typedef. Fix is in
  `compiler/nurlc.nu` — `emit_one_instantiation` re-scans the
  substituted generic-function body so concrete inner refs trigger
  `ensure_struct_instantiated`, and `ensure_struct_instantiated`
  itself re-scans the substituted generic-struct body for the same
  reason. Bootstrap fixed point holds (stage1 ≡ stage2 byte-identical
  IR at 1 187 843 B). Regression: `compiler/tests/generic_nested_struct.nu`
  (Inner/Outer + Wrap/Vec, both `[i]` and `[s]` instantiations).

* **`Channel[A]` — generic over the element type.** `stdlib/std/channel.nu`
  rewritten on top of the nested-generic fix. `Channel[A] { s ctl }`
  wraps `ChannelImpl[A] { Mutex m, Cond c, ( Vec A ) q, i closed }`;
  every call site supplies the element type via `[A]`
  (`chan_new [i]`, `chan_send [s] ch "hello"`, `chan_recv [i] ch → ?i`,
  etc.). Closes the long-standing v0.3.0 roadmap item that previously
  forced i64-only channels with `# i ptr` for handle payloads.
  `compiler/tests/channel_basic.nu` migrated to the new API (still
  exercises `[i]` so behaviour-equivalent); the regression test above
  exercises both `[i]` and `[s]`. Naming: uses `[A]` (the existing
  stdlib tparam convention) — `T` is the boolean true literal in NURL
  so cannot be a tparam name.

* **Bytes endianness primitives.** `stdlib/std/bytes.nu` gained six
  read helpers and six write helpers covering u16 / u32 / u64 in
  both big-endian (network) and little-endian byte orders:
  `bytes_read_uN_be/_le → ?T` (None when offset is negative or runs
  off the end of the buffer), and `bytes_push_uN_be/_le → v` for the
  symmetric appends. Unblocks binary protocol work (gzip CRC-32 +
  ISIZE trailers, MessagePack header bytes, BSON length prefixes,
  raw network packet headers). Regression:
  `compiler/tests/bytes_endian.nu` (round-trip + boundary values +
  byte-layout sanity + OOB + negative-offset rejection).

### Fixed

* **Nested `??` on a bare-enum value from an `F` arm of `! T E` now
  compiles.** `gen_match` was always emitting `extractvalue` to recover
  the discriminant tag, even when the matched value was already a bare
  scalar (e.g. an `IoErr` bound by `?? r { F e → ?? e { … } }`, where
  `e` is just i64). The pre-existing i1 short-circuit is generalised
  to cover both `i1` AND `i64` match types — `extractvalue` is only
  emitted on aggregate types now. Closes gotcha #6. Regression:
  `compiler/tests/nested_match_enum.nu` (direct `??` on Color, nested
  `??` per-variant on DbErr-from-`! i DbErr`, plus the wildcard arm).

* **Param name shadowing struct field name no longer miscompiles.**
  `gen_field_store`'s struct-pointer branch now routes `= . obj field
  val` to the field-store path when the IDENT after `.` is a
  function parameter AND a registered field of the destination
  struct. Pre-fix the int-width check ran first and treated the
  param as an array index, emitting `getelementptr %S, %S* %obj, i64
  %field` (value-as-index, no field offset). Local non-param int
  variables that coincide with field names — like vec.nu's
  `len`/`idx`/`i` array-store kernels — still route through the
  array path. Closes gotcha #10. Regression:
  `compiler/tests/param_field_shadow.nu` (Box param-shadow positive +
  Pt array-store negative control).

* **`i64` recognised as a type keyword.** The C and Python lexers'
  multi-char TYPE_KW whitelists already covered
  `i8`/`i16`/`i32`/`u16`/`u32`/`u64`/`f32` but not `i64`, so any
  source line writing `: i64 name …` silently took the inferred-type
  branch (`i64` as the binding name, the rest as the value) and
  produced IR with undefined SSA names. `llvm_type` was missing the
  `i64 → i64` row symmetrically — even after the lexer fix, the chain
  fell through to the `%i64` named-type fallback and LLVM rejected the
  resulting `alloca %i64` as unsized. Both ends fixed; closes gotcha
  #7. Regression: `compiler/tests/sized_int_binding.nu` covers
  literal + FFI-call RHS for every sized integer width.

* **Sign-extension when loading bytes from `*u` pointers.**
  `gen_member` now snapshots `__last_unsigned__` before parsing the
  index expression and restores it after the load, so a subsequent
  `# i ( . p k )` cast emits `zext i8 → i64` instead of `sext`. Prior
  to this, a byte with the high bit set (`0x89`, `0xFF`, …) would
  sign-extend to `0xFFFFFFFFFFFFFF89` and silently corrupt
  shift-and-add accumulators in the byte-decoding code that triggered
  the discovery. Covers both the literal-index and variable-index
  load paths; struct-field loads not affected.

### Changed

* **`Channel` is no longer a type alias for the i64 channel.** All
  callers must specify the element type at use site. The single
  in-tree caller (`compiler/tests/channel_basic.nu`) was updated.

## [0.6.0] — 2026-05-16

CSV stdlib consolidates around the arena layout, runtime link-time
optimization lands across the toolchain, and a couple of long-running
infrastructure papercuts get resolved.

### Added

* **`build.sh --no-tests` flag.** Bootstraps the compiler (with the
  byte-identical-IR fixed-point gate still enforced) and exits before
  the test suite. Replaces the older `verbosebuild.sh` script that
  Docker images relied on. `api/Dockerfile` and `nurlapi/Dockerfile`
  both updated to `./build.sh --no-tests`.

* **`nurl.sh` link line — full runtime-feature parity.** The user-
  facing wrapper now auto-links `-lssl -lcrypto` (when
  `stdlib/runtime.openssl` sentinel present), `-lsqlite3`
  (`stdlib/runtime.sqlite3`), and `-lpq` (`stdlib/runtime.pq`) in
  addition to the existing `-lcurl` auto-detection. Mirrors the
  central `build.sh` link line; closes the v0.4.3 follow-up to
  centralise the link-flag set across multiple build scripts.

### Changed

* **Runtime LTO** — `stdlib/runtime.o` is now compiled with `-O2
  -flto`, and every clang invocation that consumes it (`build.sh`,
  `nurl.sh`, `compiler/tests/run_tests.sh`,
  `tools/{nurlfmt,nurl-lsp,nurlpkg}/build.sh`) carries the matching
  `-flto` flag. The LTO link pipeline inlines Vec / String / IO FFI
  calls (`vec_push`, `vec_data`, `vec_reserve`, `nurl_peek/poke`,
  `nurl_parse_int_range`, `cmp_int`, …) across the runtime ↔ user-
  code boundary. Measured on the 1 M-row × 8-col CSV bench (Linux
  i7-5930K, 5 runs median):

  | Stage  | no LTO | LTO    | Δ       |
  |--------|-------:|-------:|--------:|
  | load   | 315 ms | 272 ms | **-14 %** |
  | filter | 146 ms | 139 ms |  -5 %   |
  | sort   |  65 ms |  40 ms | **-38 %** |
  | total  | 529 ms | 451 ms | **-15 %** |

  Sort wins the most because the indexed-permutation comparator was
  bottlenecked on un-inlinable `nurl_parse_int_range` / `cmp_int` /
  `vec_data`. Native binary size dropped 172 888 → 25 408 B (-85 %)
  as LTO drops unused runtime symbols. Bootstrap fixed-point IR
  unchanged (LTO runs at link time only — `nurlc`'s LLVM IR
  generation is invariant) — stage1 ≡ stage2 still at 1 185 386 B.

* **`stdlib/ext/csv.nu` API consolidation.** The legacy v1
  `CSVTable` / `CSVRow` per-cell-malloc layout is gone. The arena-
  backed `CSVTableA` is now THE `CSVTable` — every `csv_table_*`
  call reaches the (offset, length) arena parser directly, and
  RFC 4180 quoting is the default for every load/write. New
  accessor surface:

  - `csv_table_view t row col → s` — zero-copy borrowed pointer
    into the content / escape buffer. NOT NUL-terminated; pair with
    `csv_table_view_len`.
  - `csv_table_view_by_name`, `csv_table_view_len`.
  - `csv_table_get t row col → ?String` — owned-String fallback for
    callers that want an independent lifetime.
  - `csv_table_get_by_name`.

  All sort / filter / truncate / find / select_cols paths wired
  through the arena. Predicate signature for `csv_table_filter` is
  now `( @ b *CSVTable i ) → b` (table + row index) instead of the
  old CSVRow-based shape — match the closure-cached-pointer pattern
  used by `compare/nurl_analysis.nu`. `csv_table_a_*` functions and
  `CSVTableA` deleted outright (no deprecation cycle — NURL is not
  yet in wide enough use). Removed files:
  `stdlib/ext/csv_hoist_test.nu`, `compare/nurl_analysis_arena.nu`,
  `compiler/tests/csv_sort_indexed.nu`, `compare/csv_demo.nu`
  (latter two were duplicates of `csv_arena` / `examples/csv_demo.nu`).
  Callers updated: `examples/csv_demo.nu`, `compare/nurl_analysis.nu`,
  `compare/test_quoting.nu`, `compiler/tests/{csv_arena,
  repro_csv_table_quotes}.nu`. CSV bench at 451 ms (post-LTO) vs
  Polars 95 ms (~4.7×). RFC 4180 quoting verified across read +
  write round-trips.

* **Test framework: skip helper modules.** `compiler/tests/run_tests.sh`
  now skips files matching `*_mod.nu`, `*_helper.nu`, `*_lib.nu` —
  they are imported by other tests and have no `main` function, so
  the old framework recorded them as `COMPILE OK / LINK FAIL` in
  the baseline. Five stale entries removed from `correct.txt`:
  `alias_rewrite_types_mod`, `should_fail_alias_import_mod`,
  `should_fail_group_d_lib`, `should_fail_pub_helper`,
  `should_fail_pub_type_helper`.

### Removed

* **`verbosebuild.sh`** — duplicated `build.sh`'s logic without
  test execution. Folded into `build.sh --no-tests`.

* **`CSVTableA` + every `csv_table_a_*` function** in
  `stdlib/ext/csv.nu` (see "API consolidation" above).

* **`stdlib/ext/csv_hoist_test.nu`** — stranded Phase 2c hoist
  experiment, never imported by any caller.

## [0.5.0] — 2026-05-16

The package manager lands. `nurlpkg` is a Cargo-shaped CLI that
covers the full dependency lifecycle: scaffold a manifest, declare
dependencies, resolve them transitively, lock the resolution, and
verify the lockfile hasn't drifted. This release also ships the
TOML and Manifest stdlib modules that back the package manager,
plus a new `fs_symlink` primitive in `stdlib/std/fs.nu`.

### Added

* **`tools/nurlpkg/` — NURL package manager.** Single-binary CLI
  with ten subcommands:

  - `nurlpkg init <name>` — write a `nurl.toml` skeleton (refuses
    to overwrite an existing one).
  - `nurlpkg info` — pretty-print the typed manifest fields.
  - `nurlpkg deps` — list each `[dependencies]` entry, one per
    tab-separated line (pipe-friendly).
  - `nurlpkg add <name> [--path P] [--version V]` — append a
    dependency to `[dependencies]` via surgical text edit
    (preserves user comments and formatting; refuses duplicates).
  - `nurlpkg remove <name>` — delete a dependency entry the same
    way (errors if the name isn't declared).
  - `nurlpkg install` — BFS-resolve every path-based dependency
    transitively, create `deps/<name>` symlinks via libc's
    `symlink(2)`, regenerate `nurl.lock` as a side effect.
    Idempotent: rerunning on a fully-installed tree returns 0
    silently. Diamond dependencies dedupe.
  - `nurlpkg lock` — regenerate `nurl.lock` from the on-disk
    `deps/` tree without reinstalling.
  - `nurlpkg verify` — compare `deps/` against `nurl.lock` and
    exit 1 on any drift (missing entries OR unexpected entries).
    Intended for CI / pre-build gates.
  - `nurlpkg version` / `--version` — print the nurlpkg version.
  - `nurlpkg help` — usage.

* **`stdlib/ext/toml.nu` — TOML parser.** Recursive-descent parser
  producing a `TomlValue` tagged-union tree (`TStr` / `TInt` /
  `TBool` / `TArr` / `TTable`). Handles both `[section]` headers
  and `[[array.of.tables]]`, inline tables, dotted keys, and
  comments. Used internally by the package manager but also
  available to any stdlib consumer.

* **`stdlib/ext/manifest.nu` — typed manifest view.** Pulls the
  well-known `[package]` and `[dependencies]` fields out of a
  TomlValue tree into a typed `Manifest { name, version,
  description, license, Vec[Dep] dependencies }`. Single-table
  inline-table dep form and bare-string version form both
  supported. Returns `! Manifest ManifestErr` with a small set of
  named error variants (ReadFailed / ParseFailed / MissingName /
  MissingVersion / BadShape).

* **`fs_symlink s target s linkpath → !v IoErr` (stdlib/std/fs.nu).**
  Thin wrapper over libc's `symlink(2)` exposed via pure-NURL FFI
  (`& \`c\` @ symlink → i32`). POSIX-only; Windows callers should
  fall back to copying since `CreateSymbolicLinkW` needs a
  privilege most accounts lack.

* **Regression tests.** `compiler/tests/toml_basic.nu` covers the
  parser; `compiler/tests/manifest_basic.nu` covers the typed
  manifest extraction (well-formed + missing-required-field
  cases).

### Compiler quirks documented (workarounds in place)

Two codegen issues surfaced while writing the package manager and
remain as quirks until separately addressed:

* **Nested `??` on an enum value extracted from `! T E`** emits
  `extractvalue` on an `i64`, which is invalid LLVM. Workaround:
  flatten with `?` + `==`, or restructure to avoid needing the
  inner match (`__cmd_install` checks `file_exists` before
  `dir_create` to skip the `AlreadyExists` arm entirely).

* **Width-suffixed FFI return bindings** (`: i64 n ( ffi_call … )`)
  emit `store i64 %n, …` before the call defines `%n`, producing
  "use of undefined value." Workaround: bind FFI integer returns
  to `: i n (…)` (the default 64-bit type).

## [0.4.4] — 2026-05-16

LSP server gains the last three "quick win" features and the
Language Server protocol surface is now feature-complete enough
for daily editor use without falling back to other tooling.

### Added

* **`textDocument/formatting`** — pipes the active buffer through
  `build/nurlfmt --stdin` and returns a single TextEdit covering
  the entire document. `Shift+Alt+F` in VS Code triggers it. Uses
  `process_run`'s stdin_str parameter — no temp file needed.

* **`workspace/symbol`** — fuzzy-search across every indexed
  top-level symbol (functions, struct/enum types, enum variants,
  global constants, FFI symbols). Case-insensitive substring
  match, empty query returns the full set. `Ctrl+T` / `Cmd+T` in
  VS Code. Reuses the `g_all_names :list` TSV index built by the
  decl scanner.

* **`textDocument/foldingRange`** — emits FoldingRange for every
  multi-line `{ … }` block. Backtick strings and `//` comments are
  skipped so braces inside them don't confuse the matcher.
  Single-line blocks (e.g. `{ ^ 0 }`) are filtered out. Nested
  blocks each get their own range so the editor can fold any
  level independently.

## [0.4.3] — 2026-05-16

Tier D ecosystem advances on two axes: a working **Language Server**
(`nurl-lsp`) with the five most-used IDE features wired end-to-end,
and a small but generally-useful binary-stdin primitive in core/io.

### Added

* **NURL Language Server (`tools/nurl-lsp/`).** Stdio JSON-RPC server
  written in NURL itself, wired to VS Code / Windsurf through the
  refreshed `tooling/vscode-nurl` extension (v0.3.0). Features:
  - Live compile-driven **diagnostics** on `didOpen` / `didChange`
    (errors + warnings stream from `nurlc` stderr into LSP
    `publishDiagnostics`).
  - **Go-to-definition** across files. Transitive `$`-import index
    populated per workspace; jump works for `@`-functions,
    struct/enum types, enum variants, global `:` constants, and
    `& \`lib\`` FFI symbols.
  - **Document outline** (`textDocument/documentSymbol`) with the
    right `SymbolKind` per decl shape — visible in VS Code's
    Outline panel and via `Ctrl+Shift+O`.
  - **Hover** popups (`textDocument/hover`) showing the symbol's
    kind label, signature line (Markdown-formatted code block),
    and source location.
  - **Completion** (`textDocument/completion`) filtered by the
    IDENT-prefix immediately left of the cursor. `CompletionItemKind`
    mapping covers the same five decl shapes.

  Build: `./tools/nurl-lsp/build.sh` produces `build/nurl-lsp`.

* **`stdlib/core/io.nu read_n_bytes i n → ( Vec u )`.** Owned-Vec
  binary stdin reader. Used by the LSP server's `Content-Length`
  framing; useful for any framed-protocol consumer (DAP, raw
  JSON-RPC, length-prefixed RPC). Backed by `nurl_read_n_bytes` in
  `runtime.c §1` — single `fread` + side-channel byte count via
  the existing `nurl_last_bytes_len`.

* **`tooling/vscode-nurl` extension v0.3.0.** Spawns `nurl-lsp` over
  stdio via `vscode-languageclient`. Server-path fallback order:
  `nurl.server.path` setting → `<workspaceFolder>/build/nurl-lsp` →
  PATH lookup for `nurl-lsp`. Graceful syntax-only fallback when no
  binary resolves. New configuration knobs `nurl.server.path` and
  `nurl.server.trace`. Packaged as `nurl-0.3.0.vsix`.

### Fixed

* **`tools/nurlfmt/build.sh` linker line.** The formatter's build
  script was matching only the libcurl sentinel; missing
  openssl / sqlite3 / libpq linker flags led to `undefined reference
  to TLS_server_method` once OpenSSL was wired into the runtime.
  Now mirrors `tools/nurl-lsp/build.sh` and the central `build.sh`
  by checking all four runtime sentinels (`stdlib/runtime.{curl,
  openssl,sqlite3,pq}`) and appending the corresponding `pkg-config
  --libs` to the link line. Same pattern that breaks when a new
  runtime dependency is added across multiple build scripts —
  centralising into `tools/_link_flags.sh` is a follow-up.

## [0.4.1] — 2026-05-15

### Fixed

* **WASI build: gate setjmp/longjmp + clock() that wasi-sdk rejects.**
  The v0.4.0 panic model `#include <setjmp.h>` made `runtime.c`
  unbuildable under `--target=wasm32-wasi` (wasi-sdk's setjmp.h
  errors out unless `-mllvm -wasm-enable-sjlj` is set against the
  unfinalised Wasm Exception Handling proposal). Same for `clock()`,
  which is deprecated on wasi-sdk without `_WASI_EMULATED_PROCESS_CLOCKS`.
  Both are now `#ifndef __wasi__`-guarded. On WASI, `nurl_recover`
  degrades to "run-the-closure-inline, return 0"; `nurl_panic` prints
  the message and aborts (same shape as the no-frame path on native
  targets); `nurl_panic_last_msg` returns `""`. The degraded recover
  semantics line up with WASI's other single-threaded fallbacks
  (signals, processes, threads). Native builds unchanged — bootstrap
  fixed point still at 1 184 466 B.

## [0.4.0] — 2026-05-15

Tier A correctness/safety holes from the v0.3.0 external review all
closed; Tier B HTTP production-hardening complete end-to-end (TLS
1.2+, per-request timeout, configurable parser limits, handler panic
recovery); Tier C module-system extended (`pub` for types/enums/
consts, alias rewrite for everything); Tier D ecosystem advanced
(SQLite + PostgreSQL FFI, compile-time FFI library check).

The full per-feature breakdown follows.

### Added

* **PostgreSQL FFI in `stdlib/ext/postgres.nu` (pure-NURL).** First
  example of the **runtime-less FFI model**: every libpq symbol is
  declared directly via `& `pq` @ ... → ...` — no `runtime.c` bridge.
  Surface: `pg_connect / _close / _err_msg / _exec / _exec_params /
  _result_status / _result_is_ok / _ntuples / _nfields / _get_value /
  _get_is_null / _field_name / _clear`. `pg_exec_params` accepts a
  `Vec[String]` and builds the parallel `char **` pointer array for
  libpq. v1 scope: text format only, no async, no LISTEN/NOTIFY, no
  COPY streaming. Build-time dep detected via `pkg-config --exists
  libpq`; missing → clear compile-time error from the new lib-check
  (below). Regression: `compiler/tests/postgres_basic.nu`
  (NURL_PG_TESTS=1 + PG_CONNINFO=... to enable).

* **Compile-time FFI library presence check
  (`__ffi_lib_check`).** Every `&`-FFI library name is normalised
  (strip `lib`-prefix, whitelist always-linked system libs `c` / `m` /
  `pthread` / `dl`) and checked against `stdlib/runtime.<lib>`
  sentinels written by `build.sh`. Missing sentinel → die at the
  `&`-decl site with `FFI library '<name>' is required but no
  build-time sentinel '...' found - install lib<name>-dev (or
  equivalent) and run build.sh again`. Replaces cryptic linker errors
  like `undefined reference to PQconnectdb`. Smoke-validated by moving
  `stdlib/runtime.pq` aside and recompiling a postgres-using program.

* **SQLite FFI in `stdlib/ext/sqlite.nu`.** Thin wrapper over
  libsqlite3 with idiomatic `! T SqliteErr` returns. Surface:
  `sqlite_open / _close / _exec / _prepare / _bind_int / _bind_text /
  _bind_null / _step / _column_count / _column_type / _column_int /
  _column_text / _reset / _finalize`. `: Database` / `: Statement`
  value handles, `: | SqliteErr` with 9 variants. `sqlite_step`
  returns `!b SqliteErr` (T=Row, F=Done). v1 scope: int64 + text
  binds/columns only (no BLOB / double), no transaction helpers, no
  statement cache, no ATTACH — those compose with raw SQL. Build-
  time dep detected via `pkg-config --exists sqlite3`; without it,
  every entry returns `SqliteUnsupported`. Runtime side at
  `stdlib/runtime.c §21`. Regression: `compiler/tests/sqlite_basic.nu`
  (in-memory CRUD round-trip with prepared statement reuse).

* **Import alias rewriting extended to types, enum variants, and
  global constants.** `$ `path` alias` now renames every top-level
  decl in the imported file to `alias__name`, not just `@`-functions.
  Use sites reach them with `alias::Name`, which the lexer merges into
  the single IDENT `alias__Name`. FFI declarations and trait/impl
  methods are NOT renamed — FFI is linker-level ABI, trait dispatch is
  type-mangled. `collect_alias_targets` grew handling for `:` /
  `: |` / `: TYPE_KW` / `pub` prefixes. Regression:
  `compiler/tests/alias_rewrite_types.nu` + helper module.

* **`pub` visibility for structs, enums, and global constants.**
  Extends the v2.0 `pub @ greet` rule that already covered `@`-fns to
  cover `pub :`, `pub : |`, and `pub : i FOO 7` declarations. Enum
  variants inherit the parent enum's visibility (no per-variant
  syntax). Enforcement at parse_type_base (cross-file `%Name`
  resolutions) and gen_ident (cross-file `__global` loads). FFI and
  trait/impl decls accept `pub` forward-compat but don't enforce
  (FFI is an ABI contract; trait dispatch is type-mangled, not name-
  routed). Diagnostic: `private type 'X' is not visible across files;
  defined in 'Y'` (and the `global` / `function` variants on the same
  template). Regressions: `pub_type_visibility.nu` (positive) +
  `should_fail_pub_type_neg` / `_const_neg` / `_variant_neg` +
  `should_fail_pub_type_helper.nu` (shared helper).

  **Strategic value:** package management now has the public API
  surface it requires.

### Changed

* **`parse_request_head` now returns `! ParsedHeadOk HttpReqErr`**
  (was `ParsedHead { head, consumed, ok, err }`). The v0.3.0-era
  tagged-struct workaround for the multi-field-Result-Ok-arm hole is
  gone — heap-boxing of multi-field Ok payloads shipped 2026-05-14
  unblocked the idiomatic shape. Callers in `stdlib/ext/http_server.nu`
  (`__read_request_head` + keep-alive loop), `stdlib/ext/http_proxy.nu`
  (`proxy_serve_run_with`), and `compiler/tests/http_request_parser.nu`
  migrated from `? . ph ok / .ph err` branching to `?? ph { T pho → ...
  F e → ... }`. `parsed_head_free` and `__parsed_head_err` removed —
  the new shape needs neither. Bundled cleanup: stale `vec_get [Header]`
  miscompile comments in `header_get` / `__parse_headers` updated to
  reflect current reality (the miscompile shipped a fix May 14;
  direct-pointer iteration is retained where it's still the right
  shape, not as a workaround).

### Added

* **Panic model + HTTP handler panic recovery.** New
  `stdlib/std/panic.nu` module: `panic s msg → v` for explicit aborts,
  `recover ( @ v ) closure → ! v PanicInfo` for setjmp/longjmp-based
  catch. Built on `nurl_recover` / `nurl_panic` / `nurl_panic_last_msg`
  runtime primitives (`stdlib/runtime.c` §20, thread-local jmp_buf
  stack). NOT Rust-style stack unwinding — owned allocations inside a
  recover scope that don't run their auto-drop **leak**. Signal faults
  (SIGSEGV / SIGFPE / SIGBUS) are NOT caught. Recover is crash-
  mitigation, not a routine error path. HttpServer's
  `__serve_keepalive_loop` wraps the handler call in `recover`: panic
  in the handler → server logs the message to stderr + substitutes
  a stock 500 response + keeps serving. Compiler fix bundled:
  `simple_capture_analysis` now captures assignment targets as well
  as read references — the recover-with-byref-capture pattern depended
  on it (pre-fix the closure body referenced the outer's alloca
  register directly, producing invalid IR). Regressions:
  `compiler/tests/recover_basic.nu` (offline; Ok / panic / typed-byref
  round-trip cases) and `compiler/tests/http_server_panic.nu`
  (NURL_NET_TESTS=1).

* **TLS (server-side) via libssl/OpenSSL.** `tcp_listen_tls host port
  cert_path key_path → !TcpListener NetErr` in `stdlib/std/net.nu` is a
  drop-in replacement for `tcp_listen`; `NurlTcp` runtime struct made
  polymorphic via `SSL *ssl` + `SSL_CTX *ssl_ctx` fields, so
  `nurl_tcp_read` / `_write` / `_close` dispatch via libssl when the
  handle was wrapped at listen time. **HttpServer integration is zero
  code changes** — callers just swap the listener constructor. TLS
  1.2 minimum. Build-time dependency detected via `pkg-config --exists
  openssl`; without it, calls return `NetTlsCtxInit`. v1 scope: no
  SNI, no ALPN, no client-cert auth, no live cert reload. New `NetErr`
  variants: `NetTlsCtxInit` / `NetTlsCertLoad` / `NetTlsKeyLoad` /
  `NetTlsHandshake`. Regression:
  `compiler/tests/http_server_tls.nu` (NURL_NET_TESTS=1; generates a
  self-signed cert at setup time).

* **HTTP server Phase 8 closed out.** Two production-hardening items
  shipped:
  - *Configurable parser limits* via new `HttpLimits { i head_max_bytes,
    i header_max_count, i body_default_max }` struct + `http_default_limits`
    ctor in `stdlib/ext/http_request.nu`. `parse_request_head_with` /
    `__parse_headers` / `__finish_body` plumbed; `HttpServer` extended
    with an `HttpLimits limits` field; new `server_new_complete`
    constructor exposes every knob. Existing `server_new` / `_with_timeout`
    / `_full` keep v0.3.0 defaults so every existing call site builds
    unchanged.
  - *Per-request total timeout* via new `HttpServer.request_total_timeout_ms`
    field (0 = disabled). `__serve_keepalive_loop` snapshots `now_ms`
    after each head parse; if the handler runs over budget, its response
    is dropped and a stock 504 sent instead with forced `Connection:
    close`. Enforcement is post-handler only (NURL has no thread-
    cancellation primitives) — per-conn idle timeout still covers slow
    reads.

  Acceptance: `compiler/tests/http_server_limits.nu` (NURL_NET_TESTS=1).
  Mirror call site in `stdlib/ext/http_proxy.nu` uses
  `http_default_limits`.

* **Compiler warnings for `docs/GOTCHAS.md` items 3 + 8.** Two
  non-fatal `warning:` diagnostics now surface the two soundness-
  adjacent foot-guns flagged by the v0.3.0 external review:
  - *Same-line parameter shadowing* (`: i z + z 7` where `z` is a
    function parameter): per-fn `__fn_param_names__` roster shadowed
    inside closure bodies so the check stays scoped. Zero false
    positives across the entire stdlib + compiler + test corpus.
  - *Closure-byref escape on `^`-return*: closures that take a
    `: ~`-mutable multi-field capture by pointer (via the existing
    `__is_capture_byref` predicate) get tagged with
    `__last_closure_byref__` at the closure-literal site; the tag is
    propagated onto the binding (`<name>__captures_byref`) by
    `gen_let_or_struct`; `gen_ret` reads either form and emits the
    warning. `vec_push` / `thread_spawn` escape sites are NOT yet
    checked (documented as follow-up).

  New `should_warn_*` test category in `compiler/tests/run_tests.sh`:
  compile stderr is captured into a `WARNINGS` block (absolute paths
  stripped via `sed $ROOT_DIR/`). Regressions:
  `compiler/tests/should_warn_param_shadow.nu` and
  `compiler/tests/should_warn_closure_escape.nu`. `docs/GOTCHAS.md`
  items 3 + 8 marked "Compiler-warned 2026-05-15" in the quick-ref
  table.

### Fixed

* **`$`-import dedup keys are now canonicalised.** Pre-existing dedup
  tables in three compiler passes (`scan_generic_structs`,
  `scan_fn_sigs`, `gen_import_decl`) keyed on the raw path string, so
  `$ \`stdlib/x.nu\`` and `$ \`./stdlib/x.nu\`` (same physical file,
  different strings) defeated the dedup and produced `redefinition of
  type` errors at link. New `__norm_import_path` helper strips leading
  `./` segments at every `$`-path read site. Symlink-equivalent paths
  still collide as separate imports (no realpath FFI yet —
  intentionally deferred). Acceptance:
  `compiler/tests/import_dedup.nu`. README "Known Limitations" updated
  to drop the stale "no duplicate-include guard" / "alias parsed but
  ignored" claims (alias DOES rewrite top-level `@`-fns; dedup HAS
  worked for exact-string matches since the original `$`-import
  implementation).

* **HTTP server pipelining correctness.** The keep-alive request loop
  previously copied all bytes past a parsed head wholesale into
  `req.body`, which silently corrupted req1 and dropped req2 entirely
  when a peer pipelined two requests in one `send()`. The fix
  introduces a connection-level `Vec[u] carry` buffer that survives
  across keep-alive iterations: `__read_request_head` drops only the
  `.consumed` bytes off the front after a successful parse;
  `__finish_body` drains exactly Content-Length bytes off carry's
  front before topping up from the socket; any remaining bytes feed
  the next iteration. Mirror call site in `stdlib/ext/http_proxy.nu`
  also updated. Acceptance:
  `compiler/tests/http_server_pipelined.nu` (NURL_NET_TESTS=1).

## [0.3.0] — 2026-05-15

Grammar moved from v1.9 → **v2.0**: visibility control with `pub` is
the headline feature. `printf`-family direct-call (variadic FFI)
shipped in the same window. `nurlfmt` learned the canonical layout
and ships as `build/nurlfmt`. Bootstrap fixed point holds with
byte-identical LLVM IR across stages 1 and 2.

### Added

* **Visibility control with `pub`** (grammar v2.0). A top-level decl
  may carry a leading `pub` keyword to mark it public:

  ```nurl
  pub @ greet → v { ( nurl_print `hello\n` ) }
  @ __priv   → v { ( nurl_print `internal\n` ) }
  ```

  Per-file strict-vis mode is OPT-IN: a source file enters strict
  mode the first time any of its decls carries `pub`. In strict
  mode, every unmarked `@`-function is private to that file; calls
  from another file are rejected with
  `private function 'X' is not visible across files; defined in 'Y'`.
  Files without any `pub` decl stay in legacy mode — the entire
  existing stdlib + test corpus continues to build unchanged.

  Implementation: `LTT_PUB = 44` in `stdlib/runtime.c` (the lexer
  recognises the bare identifier `pub`); `compiler/nurlc.nu` tracks
  per-fn origin + per-file strict-mode in a new `g_vis_syms` map,
  the current source file is saved/restored across nested
  `$`-imports, and `gen_call` enforces the rule at @-fn dispatch
  sites. Forward-compat parse paths for `pub` on `:` / `&` / `%`
  decls accept the prefix but do not yet enforce — wider
  enforcement is on the roadmap. `nurlfmt` learned to glue `pub`
  onto the following decl-starter so `pub @ greet` stays on one
  line through the formatter. Regression tests:
  `compiler/tests/pub_visibility.nu` (positive, runs `hello from pub`
  + `hello from priv`) and `compiler/tests/should_fail_pub_visibility_neg.nu`
  (negative, expected `COMPILE FAIL`). Bootstrap fixed point holds
  with byte-identical IR across stages 1 and 2.

* **Variadic FFI + automatic argument promotion** (grammar v1.9).
  FFI declarations may end the param list with the literal `...`
  token to mark the C function variadic. New `LTT_ELLIPSIS = 43`
  in `stdlib/runtime.c`; `gen_ffi_decl` records `<fname>__variadic`
  + `<fname>__variadic_fixed` side-channels; `gen_call` applies the
  C default argument promotions (ISO C §6.5.2.2) to every argument
  beyond the fixed count — `float → double` via `fpext`, narrow
  ints (`i1` / `i8` / `i16`, signedness from the binding's
  `__unsigned` flag) → `i32` via `sext` / `zext`. `i32` / `i64`
  / `double` / pointers pass through unchanged. Unlocks direct
  `printf` / `snprintf` / `fprintf` / `scanf` from NURL without
  per-call hand-widening. Closes `docs/GOTCHAS.md` §9 — every
  remaining §1-10 entry is now an intentional design choice rather
  than a real bug. Canonical example:

  ```nurl
  & `libc` @ printf s fmt ... → i32

  : i32 a 42
  : f32 c # f32 3.5
  ( printf `i32=%d f32=%g\n` a c )   // both args auto-promoted
  ```

  Regression: `compiler/tests/variadic_ffi.nu` (every promotion
  rule in one exit-0 program). Bootstrap fixed point holds at
  1 125 285 B (stage1 ≡ stage2 byte-identical, +11 426 B vs Phase
  1B). `nurlfmt` round-trips `...` as a single OP token (added
  6b branch in `tools/nurlfmt/tokenize.nu`). Snapshot:
  [`spec/grammar_v1.9.ebnf`](spec/grammar_v1.9.ebnf).
* **`nurlfmt` — canonical source formatter.** First-class tooling
  for deterministic NURL source layout. Written in NURL itself
  (eats its own dogfood) and built automatically by `./build.sh`
  to `build/nurlfmt`. Specification lives in
  [`docs/FORMAT.md`](docs/FORMAT.md). CLI mirrors gofmt/rustfmt:
  `nurlfmt` (stdin→stdout), `--stdin` (explicit), `--check`
  (CI-friendly idempotence gate), `--write` (in-place), plus
  multi-file fan-out and the conventional 0/1/2 exit-code
  semantics.

  Architecture: token-stream walker — `tools/nurlfmt/tokenize.nu`
  rebuilds a comment-and-newline-preserving token vector from
  source, `tools/nurlfmt/pretty.nu` emits the canonical layout by
  tracking brace depth, top-level decl boundaries, and type-
  prefix sigil tightness (`*Expr`, `?i`, `[T]`). No CST is
  built; NURL's regular prefix grammar lets a token walker do
  the work that `gofmt` needs an AST for.

  Acceptance:
  `compiler/tests/nurlfmt_idempotent.sh` enforces two invariants
  on every `.nu` file under `stdlib/`, `examples/`,
  `compiler/tests/`, `tools/nurlfmt/`, and `compiler/nurlc.nu`:
  `fmt(fmt(x)) == fmt(x)` (formatter is a fixed point on its own
  output) AND `nurlc(fmt(x)) == nurlc(x)` byte-for-byte (the
  reformat changes zero bytes of emitted LLVM IR). 263 files
  pass idempotence; 251 are IR-equivalence covered (12 are
  include fragments that don't compile standalone and are
  skipped for the IR pass).

  v1 deliberate scope: no automatic line wrapping, no
  cascading-construct extra-indent (a user-written newline
  inside a ternary cascade gets re-indented to the surrounding
  block, not bumped by one level — see FORMAT.md §7), no comment
  reflow, no range formatting.

## [0.2.0] — 2026-05-14

First post-bootstrap release. The grammar moved from v1.7 → **v1.8**,
adding fixed-size integer and float types. Six long-standing compiler
quirks closed; the standard library no longer carries workarounds for
them. Bootstrap fixed point holds at 1 113 859 B (stage1 ≡ stage2
byte-identical LLVM IR).

### Added

* **Fixed-size integer and float types** (grammar v1.8). New TYPE_KW
  tokens `i8`, `i16`, `i32`, `u16`, `u32`, `u64`, `f32` recognised by
  the lexer. LLVM mappings: `i8` / `i16` / `i32` → `iN`; `u16` / `u32`
  → `i16` / `i32` with signedness carried in a per-binding side-
  channel (LLVM IR has no unsigned types); `u64` → `i64`; `f32` →
  `float`. Cast (`#`), let-binding store, and function-parameter
  store all consult the binding's signedness to pick `sext` (signed)
  vs `zext` (unsigned) on widening, `trunc` on narrowing. Float ↔
  double conversions use `fpext` / `fptrunc`; mixed integer/float
  paths use `fptosi` / `sitofp`.
* **Unsigned arithmetic for sized u-types.** `gen_binary` now picks
  `udiv` / `urem` / `lshr` / `icmp u*` when either operand is
  declared `u16` / `u32` / `u64` (matching the existing 8-bit `u`
  behaviour). Bitwise `&` / `|` are sign-agnostic at the LLVM level
  and previously rejected `i8` / `i16` operands; that gate was
  broadened to all integer widths.
* `CONTRIBUTING.md` with contribution guidelines and the byte-
  identical-IR bootstrap acceptance criterion.
* Google Colab notebook badge in `README.md` for one-click try-out.
* Regression tests: `compiler/tests/fixed_size_types.nu`,
  `compiler/tests/unsigned_arith.nu`,
  `compiler/tests/result_multifield.nu`,
  `compiler/tests/result_multifield_try.nu`,
  `compiler/tests/option_multifield.nu`,
  `compiler/tests/option_multifield_try.nu`,
  `compiler/tests/mutable_enum_binding.nu`,
  `compiler/tests/multifield_struct_mut.nu`,
  `compiler/tests/function_param_mut.nu`.

### Changed

* **Grammar v1.7 → v1.8.** Multi-char TYPE_KW tokens added (see
  Added). Per-binding `__nurl_type` + `__unsigned` side-channels
  drive cast / store / binop selection. No breaking changes to
  existing v1.7 programs.
* `stdlib/ext/http_server.nu` `server_run` rewritten to carry the
  failing `NetErr` variant directly through a `: ~ NetErr last_err`
  mutable binding. The previous `had_err: b` sentinel-flag dance
  plus cheap-re-issue trick is gone.
* `docs/GOTCHAS.md` rewritten for the v0.2.0 surface: historical
  bug-fix entries removed, current quirks and design notes only.

### Fixed

* **Multi-field structs on the `! T E` Ok arm.** Previously
  multi-field T couldn't fit through the i64 payload slot, forcing
  callers to wrap state in a single-pointer-handle struct or carry a
  parallel tagged-struct. The compiler now heap-boxes multi-field T
  transparently at construction (`gen_agg_lit`), unboxes at `??`
  match destructure (`gen_match`), and unboxes at `\` try-propagate
  (`gen_try_expr`). Single-pointer-handle T continues to use the
  cheaper `ptrtoint` path — no allocation.
* **Multi-field structs in `? T` Option Some arm.** Option's natural
  `{ i1, %T }` layout already handles multi-field T inline, but the
  standard `@ ? T { F # T 0 }` None-payload idiom in `vec_get` /
  `hashmap_get` / iter combinators emitted invalid IR when T's first
  field was a non-pointer named type (e.g. `%String` inside
  `Header`). `gen_cast`'s `i64 → struct` branch now returns
  `zeroinitializer` for that shape, so the None idiom works
  uniformly across stdlib.
* **Mutable enum bindings.** `: ~ NetErr e NetOther` and the
  symmetric immutable case `: NetErr e NetOther` no longer produce
  type-mismatched IR. `coerce_store_val` wraps `i64 → %Enum` with an
  `insertvalue` before the store, detected via the
  `<name>__variants` side-table. Bare-variant reassignment
  (`= last_err NetTimeout`) works for narrow and wide enums.
* **Multi-field struct mutation through closures.** When a `: ~`-bound
  multi-field struct is captured by a closure, the closure's env
  block now stores the caller's alloca *pointer* instead of
  snapshotting the value. Writes through the closure reach the
  caller's memory; immutable captures still snapshot. Lifetime
  caveat: captures are borrows — the closure must not outlive the
  binding's scope.
* **Function-parameter struct field mutation.** `= . p field val`
  on a struct parameter previously emitted invalid IR (empty GEP
  base). `gen_fn_decl_concrete` now calls `__alloca_struct_params`
  right after the function's `entry:` label; it backs each multi-
  field-struct parameter with an `alloca + store` and registers the
  pointer as the binding's `__ptr`. Value semantics are preserved
  — the function mutates a local copy; callers thread mutation
  back through the return value.

### Removed

* Obsolete test fixture removed from `compiler/tests/`.

---

## [0.1.0] — 2026-05-12

Initial public commit. Self-hosted NURL compiler targeting LLVM,
grammar v1.7. Establishes the baseline against which subsequent
releases are measured.

* Self-hosted compiler (`compiler/nurlc.nu`) with Python bootstrap
  (`compiler/nurlc.py`) and byte-identical-IR fixed-point bootstrap
  acceptance.
* Native cross-compilation targets: Linux x86_64, Windows x86_64
  (mingw-w64 + libcurl + Schannel TLS), macOS x86_64 (`zig cc` +
  libSystem only), wasm32-wasi.
* Self-hosted compiler compiles to ~390 KB of wasm and runs in a
  browser via `@bjorn3/browser_wasi_shim`.
* Single-owner memory model with compiler-inserted auto-drop
  (phases 1, 2A, 2B, 2C, 2D), user `Drop` trait, foreach-borrow
  semantics, scope-exit cleanup.
* **Standard library** under `stdlib/`:
  * `core/`: `option`, `result`, `vec`, `pair`, `string`, `errors`,
    `mem`, `io`.
  * `std/`: `fmt`, `fs`, `path`, `time` (Howard Hinnant civil-time
    algorithms, ISO-8601 + RFC 7231), `random`, `sort`, `iter`,
    `hash`, `hashmap`, `set`, `cmp`, `encode`, `channel`, `thread`,
    `signal`, `process`, `log`, `net`, `bytes`, `int`, `float`.
  * `ext/`: JSON, CSV, regex, UUID v4 + v7 (RFC 9562), env, the
    full HTTP server stack (`http`, `http_json`, `http_request`,
    `http_response`, `http_server`, `http_router`, `http_static`,
    `http_auth`, `http_middleware`, `http_multipart`, `http_proxy`,
    `http_full` aggregator), Anthropic Claude client (streaming
    SSE, prompt caching, extended thinking, tool-use loops), MCP
    client over HTTP and stdio transports.
* HTTP server: Phases 1–6 + 5.3 thread pool + 5.4 HTTP/1.1
  keep-alive (~38× speedup) + 7 (static / auth / cookies / form)
  + 8 mostly (access log, Prometheus metrics, idle timeout,
  graceful shutdown) + 9 partial (multipart/form-data, reverse-
  proxy streaming pass-through).
* 80+ snapshot tests with `compiler/tests/run_tests.sh` runner.
* Documentation: `README.md` (project overview),
  `docs/GOTCHAS.md` (compiler quirks),
  `spec/grammar.ebnf` (v1.7 grammar).
* Tooling: VS Code extension (`tooling/vscode-nurl/`), Dockerised
  compile-server (`api/`), browser playground (`nurlweb/`).
* Dual license: MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE).

[Unreleased]: https://github.com/nurl-lang/nurl/compare/v0.10.0...HEAD
[0.10.1]: https://github.com/nurl-lang/nurl/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/nurl-lang/nurl/compare/v0.9.19...v0.10.0
[0.9.14]: https://github.com/nurl-lang/nurl/compare/v0.9.13...v0.9.14
[0.9.13]: https://github.com/nurl-lang/nurl/compare/v0.9.12...v0.9.13
[0.9.12]: https://github.com/nurl-lang/nurl/compare/v0.9.11...v0.9.12
[0.9.11]: https://github.com/nurl-lang/nurl/compare/v0.9.10...v0.9.11
[0.9.10]: https://github.com/nurl-lang/nurl/compare/v0.9.9...v0.9.10
[0.9.9]: https://github.com/nurl-lang/nurl/compare/v0.9.8...v0.9.9
[0.9.8]: https://github.com/nurl-lang/nurl/compare/v0.9.7...v0.9.8
[0.9.7]: https://github.com/nurl-lang/nurl/compare/v0.9.6...v0.9.7
[0.9.6]: https://github.com/nurl-lang/nurl/compare/v0.9.5...v0.9.6
[0.9.5]: https://github.com/nurl-lang/nurl/compare/v0.9.4...v0.9.5
[0.9.4]: https://github.com/nurl-lang/nurl/compare/v0.9.3...v0.9.4
[0.9.3]: https://github.com/nurl-lang/nurl/compare/v0.9.2...v0.9.3
[0.9.2]: https://github.com/nurl-lang/nurl/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/nurl-lang/nurl/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/nurl-lang/nurl/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/nurl-lang/nurl/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/nurl-lang/nurl/compare/v0.7.3...v0.8.0
[0.2.0]: https://github.com/nurl-lang/nurl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nurl-lang/nurl/releases/tag/v0.1.0
