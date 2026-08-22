# wasmtime — a WebAssembly runtime in pure NURL

A from-scratch WebAssembly runtime written entirely in NURL — no libwasm, no
embedded interpreter, no external `wasmtime` binary. It decodes a wasm module
and executes its bytecode directly.

The motivation: NURL already compiles to `wasm32-wasi`, and packages like
[`swarm-mcp`](../swarm-mcp) ship compute kernels as wasm. Today those workers
shell out to the reference `wasmtime`. A pure-NURL runtime removes that external
dependency — a worker (or any NURL program) can host a wasm module itself.

This is a **multi-milestone** effort. The runtime decodes and executes the
full MVP instruction set with spec-correct trap semantics, plus the
multi-value, bulk-memory, reference-types and sign-extension proposals, and
hosts real `wasm32-wasi` command modules — a clang- or NURL-compiled
`hello.wasm` prints to stdout and exits through this runtime, with output and
exit code matching the reference wasmtime.

## What works now

```sh
# WASI command mode: run a wasm32-wasi module's _start (argv = module + args)
wasmtime run [--dir <path>]… [--env NAME=VALUE]… [--fuel N] [--allow-gpu] hello.wasm [args…]

# Direct mode: invoke an exported function with integer / float args
wasmtime run --invoke <export> <module.wasm> [args…]
```

- **Decoder** (`src/module.nu`) — magic/version, LEB128 (signed + unsigned),
  the type / import / function / table / memory / global / export / start /
  element / code / data sections, and the custom `name` section (function
  names for trap backtraces). Non-function imports and externref tables are
  clean decode errors. Unknown sections are skipped.
- **Interpreter** (`src/interp.nu`) — a stack machine over 64-bit integer
  cells, driven on an **explicit frame stack** (guest recursion never grows
  the host's native stack; depth-limited, optionally fuel-metered).
  Function bodies are **predecoded on first call into register form**:
  wasm validation guarantees a static stack height everywhere, so the
  value at height h lives in slot (locals+h) of one flat per-frame array
  and every record carries absolute slot indices. `local.get` is
  **forwarded** — it records that this stack height *is* the local's slot
  and emits nothing, so the consumer reads the local directly —
  `i32.const` likewise names no record: a pre-scan interns the body's
  distinct constants into a **constant pool** the frame reserves between
  the locals and the operand stack, and the const becomes an alias to
  that slot. `local.set` writes no record either: the instruction that
  produced the value is retargeted to write the local, so the copy
  disappears into its producer. `block`/`loop`/`end` emit nothing, branches
  are direct jumps carrying statically-computed result moves, and a
  compare feeding a `br_if` is **rewritten in place** into a branch that
  does its own test — no value-stack traffic and no runtime control stack.
  Execution runs two loops, not one: the outer owns the frame stack, the
  inner owns the records of a single frame and its condition is a single
  compare.
  (This landed in six steps. Flat records first — which alone took the
  JSON-parse benchmark from 31 s to 5.7 s by deleting the per-execution
  `end`-scans — then register form, roughly 2x again on straight-line
  code, then operand forwarding and the constant pool, which between them
  deleted 43 % of the records the benchmark corpus dispatches. `local.get`
  had been 45 % of all records and `i32.const` 22 % of what was left.
  Those four took a full compiler self-host on this runtime from 5m45s to
  30.5 s and then 42 % off that again.
  Then floats and the int↔float conversions left the value stack
  for register form — they were the last records bridging through it, and
  the bridge also forced an operand flush that turned every `local.get`
  feeding a float op back into a move; then `local.set` folded into its
  producer, which took `MOV` from 31 % of everything dispatched to 3 %;
  then `cmp; br_if` became one record, and the driver split into two
  loops. Measured on one workstation so the two ends are comparable, the
  benchmark corpus went 25.3 s → 13.3 s and the self-host 47.2 s → 22.7 s,
  byte-identical throughout. This round is the first where cost per record
  went *down* as well: the corpus dispatches 4.69G records before and 3.03G
  after — a **35 % cut** — at 68.5 → 51.6 host instructions each, 321G
  instructions in total against 156G. What the earlier rounds deleted was
  work per record; what this one also deleted was the per-record price of
  the loop around them.
  Then the dispatch became **one jump table over every opcode**. It had
  been a chain of range tests in measured frequency order — i64 arithmetic
  first, then the register/control forms, then i32 arithmetic, compares,
  loads, floats — so a record paid between one and seven range tests
  before its table, and then paid a *second* dispatch inside the helper it
  called (`__farith` picked one of six families, each of which picked one
  of seven ops). Written flat, one `? == op K` arm per opcode with the
  work in the arm, LLVM builds a single table: one bounds check and one
  indirect jump, and the float and integer helpers disappear into their
  arms. The corpus went 12.16 s → 9.44 s on one workstation — **22 %**,
  with nbody at −38 % and sort_window at −31 % — and 145.9G host
  instructions → 113.2G, which is 48.2 → **37.4 per record** over the same
  3.03G records. The self-host went 39.9 s → 32.4 s, byte-identical.
  A negative worth recording: doing the same to the *fused* `cmp; br_if`,
  which is 8.6 % of all records and the last caller of `__rcmp`, made the
  whole corpus **7.6 % slower**. Twenty more arms inside an existing arm
  is not the same shape as twenty arms in the table, and the driver's
  register allocation is the thing that pays.
  Last, the two linear-memory accessors are `inline` (grammar v2.7): every
  arm calls them with `n` and `signed` as literals, so an inlined copy
  folds to a bounds check, one load and a shift — but LLVM scores the
  whole callee, sees the byte-crossing path and the sign extension that
  site will never reach, and declines. Forcing it took another **9.6 %**
  off the corpus, 22 % off nbody and matmul, 14 % off sieve. Over the
  round the corpus went 12.81 s → 8.17 s — **1.57x**, nbody 2.16x, sieve
  1.86x, matmul 1.76x — and the self-host 32.6 s → 29.3 s, byte-identical
  throughout.
  Two more negatives, and the second is the useful one. **Merging the
  register/control opcodes into the same table** — renumbering them out of
  the 300s so one chain covers everything — was 8.8 % *slower*: LLVM
  partitioned the merged chain differently instead of building the one
  table it was handed. **Emitting the chain hottest-first** was exactly
  neutral; LLVM partitions by value range, not by source order. And when
  the single table was finally forced by hand, at the IR level, by
  replacing the whole compare chain with one LLVM `switch` — it *works*,
  the three levels of range test collapse to one in the disassembly, it
  removes **1.28 host instructions per record** — and the corpus does not
  move at all, ratio **1.000**. Those range tests issue alongside the real
  work and the predictor gets them right 99.9 % of the time; IPC just
  rises from 3.23 to 3.31. IPC is not what that round was waiting on;
  the round after found what was.
  Then the table stopped being one over *wasm opcodes*. What LLVM builds
  from a chain of equality tests on the same value is not one switch: it
  folds them in batches of 64, in source order, and each batch becomes its
  own jump table behind the previous batch's range check. On the wasm byte
  the used space is 0x28..0x53, 0x45..0xc4 and the register forms above it
  — sparse, in an order nothing chose — so it came out as three chained
  tables and an arm in the third paid twelve dispatch instructions where
  one in the first paid five. Renumbering the whole space **dense and in
  measured frequency order** — `__iop`, one table lookup per instruction
  at predecode time — puts the 56 opcodes that are 99 % of what a compiled
  module executes in the first batch and everything else in the second.
  No arm's body changed. Measured on one workstation, so the two ends of
  this round are comparable: the corpus went 8.35 s → 7.22 s, **15 %** by
  geometric mean, every benchmark faster, and 96.0G host instructions →
  81.4G.
  That is the same experiment the paragraph above records as neutral, with
  one thing added, and the one thing is the whole result. Merging the
  register/control forms into the numeric space and leaving the space
  sparse only moves where LLVM partitions it — which is why it measured
  8.8 % slower. (And it partitions by *source order*, in batches, not by
  value range: the earlier reading of the hottest-first experiment was
  wrong. Hottest-first over a sparse space measures neutral because it
  trades one group of arms into the first table for another; over a dense
  one it decides which 64 arms the first table holds.) Forcing a single `switch` by hand at the IR level does get
  the one table, and then spills the record's operands to the stack to
  make room for it — which is why it measured 1.000. Dense *and* ordered
  is what makes the table small enough to be free.
  Then the address add folded into the load. 57 % of every `i32.add` a
  compiled module executes is the address for the instruction immediately
  after it, so a load record grew a fourth operand — an index slot — and
  `__fuse_addr` deletes the add, handing the load its two operands
  instead. An access with nothing folded into it names pool slot 0, which
  the constant pool now reserves holding zero, so the arm adds a slot that
  is always zero rather than branching on whether it has an index at all.
  The corpus dispatches 3.12G records before and 2.98G after, and the
  memory-bound half of it moved, in cycles: bloom_filter −15 %,
  hash_join −10 %, binary_search −8 %, matmul −6 %.
  Last, the byte-crossing paths of the two accessors went out of line. An
  access whose bytes straddle two 8-byte words is a path no wasm compiler
  ever emits, and inlined it put a loop that never runs inside all
  twenty-odd access arms. Hoisting it out was another **1.9 %** with the
  host instruction count unchanged to the digit — this loop is
  instruction-cache bound, not issue bound. The same measurement from the
  other side: deleting the `--fuel` countdown outright removes 9.7 % of
  the host instructions the corpus executes and 0.3 % of its cycles, so
  the metering is free and stays exact.
  Over the round the corpus went 8.35 s → 6.93 s — **17.5 %** by geometric
  mean, every benchmark faster, nbody −32 %, ring_write −36 %,
  bloom_filter −36 % — at 96.0G host instructions → 78.3G over 3.12G →
  2.98G records, which is 30.8 → **26.3 per record**. The self-host went
  26.7 s → 25.5 s on the same module, and 21.7 s once the module itself
  was rebuilt with a toolchain fix this round turned up: `zig cc
  --target=wasm32-wasi` resolves `strlen` from its own compiler_rt shim,
  which is a byte loop, and NURL's runtime calls it on every strdup and
  every symbol-table key. A nurlc.wasm self-compile spent 4.7 of its 7.8
  billion wasm instructions inside it. The NURL runtime now defines a
  word-at-a-time `strlen` for wasm32 only (stdlib/runtime_core.c); the
  same self-compile executes 5.19G wasm instructions instead of 7.83G and
  is 12 % faster on the reference JIT as well. Byte-identical
  throughout.) Each record keeps its original
  byte offset, so trap backtraces still point into the module image:
  - structured control flow: `block`, `loop`, `if`/`else`, `br`, `br_if`,
    `br_table`, `return`, `end` — **multi-value** block types included
    (s33-encoded type-section indices; branches carry a loop's params / a
    block's results)
  - the **full** integer set with spec-correct traps: divide-by-zero and
    `INT_MIN/−1` trap, `INT_MIN rem −1` is 0; signed **and** unsigned
    `div`/`rem`/`shr`/compares, `rotl`/`rotr`, `clz`/`ctz`/`popcnt`,
    sign-extension ops, i32 results wrapped to 32 bits
  - `call` / `call_indirect` (the latter with the runtime **signature check**);
    a call leaves the inner loop, so nothing on the record path pays for it
  - **linear memory**: all sized loads/stores, `memory.size`/`memory.grow`
    (declared max + wasm32 limit honoured, −1 past them), **bulk memory**
    (`memory.copy`/`fill`/`init` with up-front bounds checks, `data.drop`,
    passive data segments), active data segments applied at instantiation.
    Instantiation is one `calloc` of the declared minimum plus one `memcpy`
    per data segment, so the pages arrive from the kernel already zero and
    untouched: a wasi command module declares 257 pages, and filling that
    16.8 MB a byte at a time used to be **78 % of the wall clock** of a run
    whose guest printed one line. Hello-world on this runtime went 50.1 ms
    → 6.7 ms on that one change, and every longer run in the corpus kept
    the same ~43 ms.
  - **globals**, **tables** + reference types: `table.get/set/grow/size/`
    `fill/copy/init`, `elem.drop`, `ref.null`/`ref.is_null`/`ref.func`,
    typed `select`; all element-segment encodings (active/passive/declared,
    index- and expression-form)
  - **floats** — register form like the integer core, full f32/f64
    arithmetic and conversions with IEEE-correct semantics: NaN-aware comparisons (`ne` true on unordered), canonical-NaN
    `min`/`max` with ±0 ordering, **trapping** float→int truncation (NaN /
    out-of-range) and true **saturating** `trunc_sat` forms, unsigned
    `convert_i64_u` via halve-with-sticky-bit (matches LLVM's lowering)
  - **imports + WASI** (`wasi_snapshot_preview1`, module name checked):
    `proc_exit`, `fd_write`/`fd_read`/`fd_seek`/`fd_tell`/`fd_pread`/
    `fd_pwrite`/`fd_sync`/`fd_datasync`/`fd_close`/`fd_readdir`, `args_*`,
    real `environ_*` (from repeatable `--env`), real `clock_time_get`
    (wall + monotonic) and `random_get` (OS entropy), `fd_prestat_*`,
    `fd_fdstat_get`, `fd_filestat_get`
  - **`--dir` preopens + path ops** (repeatable): `path_open` (O_CREAT/
    O_TRUNC/O_EXCL/O_DIRECTORY/O_APPEND semantics, rights-derived
    writability), `path_create_directory` / `path_remove_directory` /
    `path_unlink_file` / `path_rename` / `path_filestat_get`; buffered file
    writes flush on close/sync/`proc_exit`/normal exit
  - **diagnostics**: traps carry a message plus a wasm **backtrace** (name
    section names when present); `--fuel N` bounds runaway guests
    deterministically — the unit is one predecoded record, which is
    fewer than one wasm instruction (a forwarded `local.get`, a
    `block`/`loop`/`end` all cost nothing), so a budget buys more of a
    guest here than the same number would on a byte-code interpreter

```sh
# WASI command: prints to stdout, exits with the program's code
wasmtime run hello.wasm                           # → hello from wasm
# with a preopened directory, the module can read host files
wasmtime run --dir . cat.wasm input.txt           # → (contents of input.txt)

# add(i32,i32) → i32
wasmtime run --invoke add  add.wasm 40 2          # → 42
# sumto(i64) → i64   (a loop: Σ 1..n)
wasmtime run --invoke sumto sum.wasm 100000       # → 5000050000
# max(i32,i32) → i32  (if/else)
wasmtime run --invoke max  max.wasm 3 9           # → 9
```

The test suite runs hand-encoded modules whose expected results were produced by
the reference `wasmtime` — so the NURL runtime is verified against the real
thing, and is ASan-clean. `tests/wasi_test.nu` covers the import path: a module
that writes via `fd_write` and exits via `proc_exit`, matching reference output
and exit code.

## Robustness against hostile input

The decoder and interpreter are hardened against malformed / adversarial
modules: **every input is memory-safe and terminates** — no input hangs the
decoder or corrupts memory. Concretely:

- every vector length / count is validated against the bytes physically
  remaining before anything is allocated (a 10-byte module can no longer
  request a 2³²-element buffer), and `mem.min` / `table.min` / per-function
  locals are capped to architectural limits — the bound is applied to the
  count *itself*, never to a sum containing it, because a count near 2⁶³
  makes `so_far + count` wrap negative and slip past a ceiling written as
  a sum, which is a 2⁶³-iteration loop rather than a decode error;
- a LEB128 stops contributing after ten groups: past that the value cannot
  fit in 64 bits anyway, and `<< x 64` is poison in LLVM — a corrupted
  continuation byte turning a terminal group into a running one is exactly
  how a module reaches that shift;
- an active data segment that would run past the declared initial memory is
  refused at decode, where the offset, the length and `mem.min` are all in
  hand; instantiation refuses it again rather than copying what fits;
- section sizes and constant-init expressions are bounded — an over-long LEB
  size (which decodes to a negative offset) or an unterminated init expression
  is a clean decode error, not an infinite loop;
- memarg offsets are masked to `u32` so an out-of-bounds access traps rather
  than silently wrapping past the bounds check, and WASI iovec counts / buffer
  lengths are clamped to memory size;
- a function whose frame would need more than 2²⁰ slots is refused with a
  trap rather than predecoded: a ten-byte function can declare a million
  locals, and a record that packs two slot indices into one word needs the
  index to fit in twenty bits — an architectural limit, not an assumption;
- the `env`/GPU import surface is opt-in (`--allow-gpu`), off by default.

This was validated by an ASan-instrumented mutation fuzzer plus an exhaustive
prefix (truncation) sweep of the whole corpus — 7 206 runs over six modules in
the last pass, **zero crashes, zero hangs** — and locked in by
`tests/hardening_test.nu`. The sweep is re-run against every
change to the decoder or the predecoder, the two places a malformed module
reaches first. (Note: `--fuel N` still bounds
runaway *valid* guests; an unbounded `loop` runs forever exactly as it does on
the reference runtime.)

## GPU host imports (CUDA / NVRTC)

A wasm module built from a GPU-using NURL package (`packages/gpu` →
[`onnx`](../onnx) → [`objdet`](../objdet)) imports the CUDA driver + NVRTC
symbols under module `env`. This runtime resolves them to the real
`libcuda` / `libnvrtc` on the host, marshalling guest linear memory ↔ host:

- a `*u` (pointer) FFI parameter is a guest linear-memory offset → the host
  address is `vec_data(mem) + offset`; libcuda reads/writes guest memory in
  place, so `cuMemcpyHtoD` / `cuMemcpyDtoH` and every out-slot are zero-copy;
- opaque handles (`CUcontext` / `CUmodule` / `CUfunction` / `nvrtcProgram`)
  and `CUdeviceptr` travel as raw `i64` values (the portable handle model in
  `packages/gpu`, so nothing truncates on wasm's 32-bit pointers);
- `cuLaunchKernel`'s guest `void**` argument array is reconstructed as a host
  `void**` with each entry translated to its host address.

`nurl.sh` auto-links `libcuda`/`libnvrtc` when these symbols appear and links
stub objects on a GPU-less host, so `wasmtime` always builds; a guest then
just sees non-zero `CUresult` codes.

The `env`/GPU import surface is **off by default** — those imports hand the
guest raw host pointers into linear memory and forward them to `libcuda`, so
they are only safe for trusted compute. Pass `--allow-gpu` to enable them (the
embedder API is `interp_allow_gpu`); without it, an `env` import traps cleanly.

```sh
# a GPU wasm module runs its kernels on the real device through this runtime
wasmtime run --allow-gpu --dir . infer.wasm   # onnx forward pass on the GPU
```

Verified on an RTX 4090: a self-contained vector-add (NVRTC compile → module
load → alloc → HtoD → launch → DtoH) and the `onnx` package's inference test
(a full GPU forward pass) both run through this runtime with output
**identical to native** — the `onnx` test even matches its onnxruntime
reference. See the top-level PR for the toolchain path (compile a GPU package
to wasm with FFI symbols as host imports).

> Security note: this surface is **off by default** and only enabled with
> `--allow-gpu`, because raw host handles / device pointers are visible to the
> guest exactly as in native NURL — safe for trusted compute (your own
> kernels), not for untrusted guests. A hardened untrusted-guest deployment
> would additionally add an id↔pointer handle table in the bridge; the seam is
> a single `__gpu_ptr` / handle-passthrough boundary.

## Roadmap

The integer + float core and the WASI command surface are done; hosting larger
`wasm32-wasi` programs (and eventually self-hosting the NURL compiler) needs,
roughly in order:

1. ~~**Linear memory** + `i32`/`i64` load/store (and `memory.size`/`grow`), plus
   the data section.~~ **Done.**
2. ~~**Globals**, **tables** + `call_indirect`.~~ **Done.**
3. ~~**Floats** (`f32`/`f64`) and the numeric conversions.~~ **Done.**
4. ~~**Imports + the WASI surface**: `proc_exit`, `fd_write` (stdout), `args_*`,
   and the import dispatch that lets clang output start.~~ **Done.**
5. ~~**`--dir` preopen + file ops** (`path_open`, `fd_read`, `fd_seek`,
   `fd_close`, real `fd_prestat_*`): give a module one host directory and nothing
   else — the minimal capability.~~ **Done** (read path + buffered write).

With the file layer in place, `swarm-mcp` workers can drop the external
`wasmtime` dependency and run kernels on this runtime.

### Toward self-hosting

The end goal is to run the NURL compiler itself as `nurlc.wasm` and have it
compile NURL. **The runtime side is done, and the loop closes** (with one
caveat): `nurlc.wasm --no-borrowck nurlc.nu` compiles the full 65k-line
compiler **byte-identically to the native compiler** — the first complete
self-host compile under wasm.

The caveat is memory, not correctness: self-compiling nurlc keeps ~11.7 GB
of allocations live (native peak RSS), and wasm32 linear memory tops out at
4 GiB. With the borrow checker on, the ceiling is hit mid-analysis; the
long-standing "self-host hang" was malloc returning NULL there — address 0
is writable linear memory on wasm32, so NULL-backed strings silently
corrupted the analysis state instead of crashing (identically under this
runtime and the reference wasmtime). The runtime now aborts loudly on OOM
(`nurl: out of memory`). Full self-host *with* borrowck needs the
compiler's live set under 4 GiB (or memory64).

## Layout

```
src/module.nu   wasm binary decoder: byte cursor, LEB128, sections (incl. imports), the module model
src/interp.nu   the stack-machine interpreter: control flow, integer + float ops, the WASI host calls
src/main.nu     CLI: WASI command mode (run _start) and direct --invoke mode
```

## Tests

```sh
NURL_STDLIB=<repo> ../../nurl.sh tests/interp_test.nu /tmp/it && /tmp/it
NURL_STDLIB=<repo> ../../nurl.sh tests/wasi_test.nu  /tmp/wt && /tmp/wt
# (also: mem_test, table_test, float_test)
```

## License

MIT OR Apache-2.0.
