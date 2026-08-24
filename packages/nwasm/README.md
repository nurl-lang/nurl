# nwasm — a WebAssembly runtime in pure NURL

A from-scratch WebAssembly runtime written entirely in NURL — no libwasm, no
embedded engine, no external runtime binary. It decodes a wasm module and
executes its bytecode directly, in-process.

The motivation: NURL already compiles to `wasm32-wasi`, and packages like
[`swarm-mcp`](../swarm-mcp) ship compute kernels as wasm. A pure-NURL runtime
removes the external dependency — a worker (or any NURL program) can host a
wasm module itself, including inside a NURL unikernel guest.

The CLI mirrors the subset of the reference `wasmtime` interface that this
runtime covers, so it is a drop-in for `run --dir/--env/--fuel/--invoke`
usage. (`wasmtime` here means the external Bytecode Alliance runtime; it is
this project's cross-check oracle and benchmark baseline, nothing more.)

## Usage

```sh
# WASI command mode: run a wasm32-wasi module's _start (argv = module + args)
nwasm run [--dir <path>]… [--env NAME=VALUE]… [--fuel N] [--allow-gpu] [--allow-net] hello.wasm [args…]

# Direct mode: invoke an exported function with integer / float args
nwasm run --invoke <export> <module.wasm> [args…]
```

```sh
# WASI command: prints to stdout, exits with the program's code
nwasm run hello.wasm                           # → hello from wasm
# with a preopened directory, the module can read host files
nwasm run --dir . cat.wasm input.txt           # → (contents of input.txt)

# add(i32,i32) → i32
nwasm run --invoke add  add.wasm 40 2          # → 42
# sumto(i64) → i64   (a loop: Σ 1..n)
nwasm run --invoke sumto sum.wasm 100000       # → 5000050000
# max(i32,i32) → i32  (if/else)
nwasm run --invoke max  max.wasm 3 9           # → 9
```

## What it implements

**Decoder** (`src/module.nu`) — magic/version, LEB128 (signed + unsigned), the
type / import / function / table / memory / global / export / start / element /
code / data sections, and the custom `name` section (function names for trap
backtraces). Non-function imports and externref tables are clean decode errors.
Unknown sections are skipped.

**Interpreter** (`src/interp.nu`) — a stack machine over 64-bit integer cells,
driven on an **explicit frame stack**, so guest recursion never grows the host's
native stack (depth-limited, optionally fuel-metered; 1M-deep guest recursion is
verified).

Function bodies are **predecoded on first call into register form**. wasm
validation guarantees a static stack height everywhere, so the value at height
*h* lives in slot (locals + *h*) of one flat per-frame array and every record
carries absolute slot indices:

- `local.get` is **forwarded** — it records that this stack height *is* the
  local's slot and emits nothing, so the consumer reads the local directly.
- `i32.const` names no record either: a pre-scan interns the body's distinct
  constants into a **constant pool** the frame reserves between the locals and
  the operand stack, and the const becomes an alias to that slot.
- `local.set` writes no record: the instruction that produced the value is
  retargeted to write the local, so the copy disappears into its producer.
- `block` / `loop` / `end` emit nothing; branches are direct jumps carrying
  statically-computed result moves.
- A compare feeding a `br_if` is **rewritten in place** into a branch that does
  its own test.
- An `i32.add` that computes a load's address is **folded into the load** as a
  fourth (index) operand.

The result is no value-stack traffic anywhere — floats and the int↔float
conversions are register-form too — no runtime control stack, and no LEB128 or
end-scanning at execution time. Each record keeps its original byte offset, so
trap backtraces still point into the module image.

Execution runs two loops, not one: the outer owns the frame stack, the inner
owns the records of a single frame and its condition is a single compare.
Dispatch is **one jump table** with the work inline in each arm, over a dense
internal opcode space (`__iop`, one table lookup per instruction at predecode
time) ordered by measured frequency, so the ~56 opcodes that are 99 % of what a
compiled module executes share one bounds check and one table.

Instantiation is one zero-filled allocation of the declared memory minimum plus
one `memcpy` per data segment, so start-up does not scale with the size of the
guest's heap.

### Instruction coverage

- **Structured control flow**: `block`, `loop`, `if`/`else`, `br`, `br_if`,
  `br_table`, `return`, `end` — **multi-value** block types included
  (s33-encoded type-section indices; branches carry a loop's params / a block's
  results).
- **The full integer set** with spec-correct traps: divide-by-zero and
  `INT_MIN/−1` trap, `INT_MIN rem −1` is 0; signed **and** unsigned
  `div`/`rem`/`shr`/compares, `rotl`/`rotr`, `clz`/`ctz`/`popcnt`,
  sign-extension ops, i32 results wrapped to 32 bits.
- **`call` / `call_indirect`** (the latter with the runtime **signature
  check**); a call leaves the inner loop, so nothing on the record path pays
  for it.
- **Linear memory**: all sized loads/stores, `memory.size`/`memory.grow`
  (declared max + wasm32 limit honoured, −1 past them), **bulk memory**
  (`memory.copy`/`fill`/`init` with up-front bounds checks, `data.drop`,
  passive data segments), active data segments applied at instantiation.
- **Globals**, **tables** + reference types: `table.get/set/grow/size/`
  `fill/copy/init`, `elem.drop`, `ref.null`/`ref.is_null`/`ref.func`, typed
  `select`; all element-segment encodings (active/passive/declared, index- and
  expression-form).
- **Floats** — register form like the integer core, full f32/f64 arithmetic and
  conversions with IEEE-correct semantics: NaN-aware comparisons (`ne` true on
  unordered), canonical-NaN `min`/`max` with ±0 ordering, **trapping**
  float→int truncation (NaN / out-of-range) and true **saturating** `trunc_sat`
  forms, unsigned `convert_i64_u` via halve-with-sticky-bit (matches LLVM's
  lowering).
- **Atomics** — the `0xfe` family; see [Threads](#threads-wasi-threads).
- **Imports + WASI** (`wasi_snapshot_preview1`, module name checked):
  `proc_exit`, `fd_write`/`fd_read`/`fd_seek`/`fd_tell`/`fd_pread`/`fd_pwrite`/
  `fd_sync`/`fd_datasync`/`fd_close`/`fd_readdir`, `args_*`, real `environ_*`
  (from repeatable `--env`), real `clock_time_get` (wall + monotonic) and
  `random_get` (OS entropy), `fd_prestat_*`, `fd_fdstat_get`,
  `fd_filestat_get`, `poll_oneoff`.
- **`--dir` preopens + path ops** (repeatable): `path_open` (O_CREAT/O_TRUNC/
  O_EXCL/O_DIRECTORY/O_APPEND semantics, rights-derived writability),
  `path_create_directory` / `path_remove_directory` / `path_unlink_file` /
  `path_rename` / `path_filestat_get`; buffered file writes flush on
  close/sync/`proc_exit`/normal exit.
- **Diagnostics**: traps carry a message plus a wasm **backtrace** (name-section
  names when present). `--fuel N` bounds runaway guests deterministically — the
  unit is one predecoded record, charged where time actually accumulates: each
  backward branch pays its loop body's record count and each call pays one, so
  straight-line code between them runs uncharged (it is bounded by the module
  itself). The trap lands on the back edge rather than mid-body.

Proposals supported: multi-value, bulk memory, reference types, sign extension,
threads/atomics, saturating float→int conversion.

The test suite runs hand-encoded modules whose expected results were produced by
the reference `wasmtime`, so the runtime is verified against an independent
implementation, and is ASan-clean.

## Robustness against hostile input

The decoder and interpreter are hardened against malformed / adversarial
modules: **every input is memory-safe and terminates** — no input hangs the
decoder or corrupts memory. Concretely:

- every vector length / count is validated against the bytes physically
  remaining before anything is allocated (a 10-byte module cannot request a
  2³²-element buffer), and `mem.min` / `table.min` / per-function locals are
  capped to architectural limits — the bound is applied to the count *itself*,
  never to a sum containing it, because a count near 2⁶³ makes
  `so_far + count` wrap negative and slip past a ceiling written as a sum;
- a LEB128 stops contributing after ten groups: past that the value cannot fit
  in 64 bits anyway, and `<< x 64` is poison in LLVM — a corrupted continuation
  byte turning a terminal group into a running one is exactly how a module
  reaches that shift;
- an active data segment that would run past the declared initial memory is
  refused at decode, where the offset, the length and `mem.min` are all in
  hand; instantiation refuses it again rather than copying what fits;
- section sizes and constant-init expressions are bounded — an over-long LEB
  size (which decodes to a negative offset) or an unterminated init expression
  is a clean decode error, not an infinite loop;
- memarg offsets are masked to `u32` so an out-of-bounds access traps rather
  than silently wrapping past the bounds check, and WASI iovec counts / buffer
  lengths are clamped to memory size;
- a function whose frame would need more than 2²⁰ slots is refused with a trap
  rather than predecoded: a ten-byte function can declare a million locals, and
  a record that packs two slot indices into one word needs the index to fit in
  twenty bits;
- the `env`/GPU import surface is opt-in (`--allow-gpu`), off by default.

This is validated by an ASan-instrumented mutation fuzzer plus an exhaustive
prefix (truncation) sweep of the whole corpus — 7 206 runs over six modules in
the last pass, **zero crashes, zero hangs** — and locked in by
`tests/hardening_test.nu`. The sweep is re-run against every change to the
decoder or the predecoder, the two places a malformed module reaches first.
(`--fuel N` still bounds runaway *valid* guests; an unbounded `loop` runs
forever exactly as it does on any other runtime.)

## Threads (wasi-threads)

A module built for threads — `wasmbuilder --threads` — declares a SHARED
memory, imports `wasi.thread-spawn` and exports `wasi_thread_start`. This
runtime implements that: a spawn creates a host thread with its own Interp —
own value stack, own frames, own globals, and therefore its own
`__stack_pointer` — over the *same* linear memory, table and module. The host
sets that stack pointer from the block the guest passes, because C cannot
assign a wasm global; everything else about the thread is the guest's own libc
code in `stdlib/runtime_ffi.c`.

- **Atomics** (the `0xfe` family) execute: load/store at every width, the six
  read-modify-write groups, cmpxchg, `wait32`/`wait64`/`notify` and `fence`. An
  interpreter cannot borrow the CPU's atomicity for an RMW it performs in three
  steps, so every atomic op takes one process-wide lock — sequentially
  consistent by construction. Unaligned or out-of-bounds atomics trap, as the
  spec says.
- **A shared memory is reserved at its declared maximum** when the module is
  instantiated, and `memory.grow` only raises the addressable bound: growth
  must never move a buffer another thread is reading. The new bound is
  published to every thread of the instance under the same lock.
- **The host-side tables are shared**: file descriptors, socket handles and
  captured output belong to the instantiating Interp, so a file opened by one
  thread is the same fd in another.
- **`poll_oneoff`** is implemented (clock subscriptions sleep, fd subscriptions
  on files and stdio are ready immediately), which is what libc's
  `sleep`/`nanosleep` and every timeout go through.
- A thread that traps says so on stderr and ends that thread only — the guest's
  `join` on it simply never completes, exactly as a native runtime would leave a
  crashed thread.

The guest side is worth knowing about: wasm32's libc allocator is
single-threaded by design and cannot be locked from outside, so a threads build
brings its own — `stdlib/runtime_wasm_alloc.c` defines the whole C allocation
surface behind one futex — and the stdlib's M:N async runtime (fibers) is backed
by one thread per fiber, which is what makes `spawn` + `runtime_run` (the
relay's accept loop, the HTTP server) work.

```sh
wasmbuilder --threads server.nu -o server.wasm
nwasm run --allow-net server.wasm
```

## Sockets (`nurl_net` host imports)

WASI preview1 has no way to open a socket — it can only accept on one the host
preopened — so stdlib's socket layer under `__wasi__` is a set of thin wrappers
over wasm imports in the module `nurl_net`, and this runtime answers them with
the very same `nurl_tcp_*` / `nurl_udp_*` / `nurl_dns_*` runtime entry points a
native build links directly. A NURL program that listens, connects, resolves and
serves works compiled to wasm exactly as it does natively — **including TLS**,
because stdlib's TLS 1.3 is pure NURL and runs inside the guest over these
plaintext sockets.

Two details make the bridge safe to hand an untrusted module:

- **The guest never sees a host handle.** It gets an index into a per-instance
  table; a forged handle can only miss. (It is also what makes handles work at
  all on wasm32: a host handle is a 64-bit pointer and the guest's stdlib keeps
  socket handles in a pointer-sized field.)
- **Every guest pointer is bounds-checked** against linear memory before the
  host sees it, and host-produced text (peer/local address, DNS answers) is
  copied into a guest-supplied buffer with an explicit cap.

The surface is **off by default**: pass `--allow-net` (embedder API:
`interp_allow_net`), otherwise a `nurl_net` import traps with a message that
says so. Sockets the guest leaves open are closed when the instance is freed.

```sh
nwasm run --allow-net server.wasm     # the guest's listen/accept is ours
```

A module that never touches `std/net.nu` carries no `nurl_net` import at all
(`--gc-sections` drops the unused wrappers), so it still runs on any plain WASI
runtime.

## GPU host imports (CUDA / NVRTC)

A wasm module built from a GPU-using NURL package (`packages/gpu` →
[`onnx`](../onnx) → [`objdet`](../objdet)) imports the CUDA driver + NVRTC
symbols under module `env`. This runtime resolves them to the real `libcuda` /
`libnvrtc` on the host, marshalling guest linear memory ↔ host:

- a `*u` (pointer) FFI parameter is a guest linear-memory offset → the host
  address is `vec_data(mem) + offset`; libcuda reads/writes guest memory in
  place, so `cuMemcpyHtoD` / `cuMemcpyDtoH` and every out-slot are zero-copy;
- opaque handles (`CUcontext` / `CUmodule` / `CUfunction` / `nvrtcProgram`) and
  `CUdeviceptr` travel as raw `i64` values (the portable handle model in
  `packages/gpu`, so nothing truncates on wasm's 32-bit pointers);
- `cuLaunchKernel`'s guest `void**` argument array is reconstructed as a host
  `void**` with each entry translated to its host address.

`nurl.sh` auto-links `libcuda`/`libnvrtc` when these symbols appear and links
stub objects on a GPU-less host, so `nwasm` always builds; a guest then just
sees non-zero `CUresult` codes.

The `env`/GPU import surface is **off by default** — those imports hand the
guest raw host pointers into linear memory and forward them to `libcuda`, so
they are only safe for trusted compute. Pass `--allow-gpu` to enable them (the
embedder API is `interp_allow_gpu`); without it, an `env` import traps cleanly.

```sh
# a GPU wasm module runs its kernels on the real device through this runtime
nwasm run --allow-gpu --dir . infer.wasm   # onnx forward pass on the GPU
```

Verified on an RTX 4090: a self-contained vector-add (NVRTC compile → module
load → alloc → HtoD → launch → DtoH) and the `onnx` package's inference test (a
full GPU forward pass) both run through this runtime with output **identical to
native** — the `onnx` test even matches its onnxruntime reference.

> Security note: this surface is **off by default** and only enabled with
> `--allow-gpu`, because raw host handles / device pointers are visible to the
> guest exactly as in native NURL — safe for trusted compute (your own
> kernels), not for untrusted guests. A hardened untrusted-guest deployment
> would additionally add an id↔pointer handle table in the bridge; the seam is a
> single `__gpu_ptr` / handle-passthrough boundary.

## The template JIT

On a hosted x86-64 build the predecoded records are lowered to machine code per
function and run natively; everything else — other architectures, wasm32 builds
of `nwasm` itself, metered (`--fuel`) and shared-memory (threads) runs —
executes on the interpreter, which remains the semantic reference.
`NURL_NWASM_JIT=0` turns the JIT off.

- **Templates, not an optimizer.** Each record maps to a fixed x86-64 sequence
  against the frame's register file (`disp32(%rbx)` slots); branches patch
  rel32s over a per-function label table, `br_table` becomes a clamped indirect
  jump through a table of absolute addresses, and a one-register cache elides
  the reload when a record's first operand is the value the previous record just
  stored. Constant operands are emitted as immediates, and a compare's flags
  feed the `select`s behind it.
- **Function-wide slot pinning.** The hottest integer slots of a function are
  pinned into callee-saved registers for its whole body, and pure-f64 slots ride
  in `xmm8`–`xmm11`. `NURL_NWASM_PIN=0` keeps every slot in memory (A/B, debug).
- **The interpreter handles what templates can't.** A function with any record
  outside the template set stays interpreted — per function, not per module.
  Calls out of JIT code (imports, `memory.grow`, the bulk-memory/`fc` bridge,
  `call_indirect` resolution) return to a driver that does the work with the
  interpreter's own machinery and re-enters the code at a resume point, so both
  engines always agree — the correctness gate is byte-identical output across
  both, including a `nurlc.wasm` self-compile.
- **Traps carry their real message** (`unreachable`, `integer divide by zero`,
  bounds), same text as the interpreter; JIT frames don't record positions, so
  backtraces come from interpreted frames only.
- **Guard-page memory.** On Linux/x86-64 (glibc, non-ASan) a non-shared linear
  memory is an 8 GiB `PROT_NONE` reservation with the live pages committed in
  place, so the emitted code carries no bounds checks at all: every address a
  masked 32-bit index plus a u32 offset can form lands inside the reservation,
  an access past the committed pages faults, and the runtime's `SIGSEGV` handler
  steers the faulting frame to that function's out-of-bounds stub — the same
  trap, the same message, the explicit check just never executes. Growth never
  moves the base (`memory.grow` is an `mprotect`, not a realloc). Where the
  plumbing is unavailable the memory falls back to a heap buffer and the JIT
  emits its checks; `NURL_NWASM_GUARD=0` forces that path.

`NURL_NWASM_JIT_DUMP=1` emits every sealed code page as decimal bytes on stderr.

## Performance

Numbers are measured and refreshed by `bench/wasmbench.sh` in the NURL repo;
the current report is [`bench/WASMRESULTS.md`](../../bench/WASMRESULTS.md),
which compares this runtime against the reference Cranelift JIT over the same
wasm modules. Two figures worth stating here:

- the JIT runs the benchmark corpus at roughly **0.41×** the interpreter's wall
  clock (local, best-of-3), with the memory-bound rows near 0.25× and
  call-dominated `fib` at parity;
- read any single-machine corpus ratio as "this is what one machine did".
  `wasmbench.sh` measures one revision on one runner, and a runner swap moves
  every column by more than most individual changes do.

## Self-hosting

The NURL compiler runs on this runtime: `nurlc.wasm --no-borrowck nurlc.nu`
compiles the full 65k-line compiler **byte-identically to the native compiler**.

The remaining caveat is memory, not correctness: self-compiling `nurlc` keeps
~11.7 GB of allocations live (native peak RSS), and wasm32 linear memory tops
out at 4 GiB. With the borrow checker on, the ceiling is hit mid-analysis. The
runtime aborts loudly on OOM (`nurl: out of memory`) rather than handing back a
NULL that address 0 makes writable on wasm32. Full self-host *with* borrowck
needs the compiler's live set under 4 GiB, or memory64.

## Layout

```
src/module.nu   wasm binary decoder: byte cursor, LEB128, sections (incl. imports), the module model
src/interp.nu   the stack-machine interpreter + template JIT: control flow, integer + float ops, the WASI host calls
src/main.nu     CLI: WASI command mode (run _start) and direct --invoke mode
```

## Tests

```sh
NURL_STDLIB=<repo> ../../nurl.sh tests/interp_test.nu /tmp/it && /tmp/it
NURL_STDLIB=<repo> ../../nurl.sh tests/wasi_test.nu  /tmp/nwasm && /tmp/nwasm
# (also: mem_test, table_test, float_test, semantics_test, hardening_test,
#  atomics_test)

# End-to-end: the same NURL program built native and as wasm, both talking
# to real sockets, output compared. Needs ../wasmbuilder.
./tests/net_test.sh

# Same idea for wasi-threads: four threads over one shared heap.
./tests/threads_test.sh
```

## License

MIT OR Apache-2.0.
