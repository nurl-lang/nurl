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
wasmtime run [--dir <path>]… [--env NAME=VALUE]… [--fuel N] hello.wasm [args…]

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
  the host's native stack; depth-limited, optionally fuel-metered):
  - structured control flow: `block`, `loop`, `if`/`else`, `br`, `br_if`,
    `br_table`, `return`, `end` — **multi-value** block types included
    (s33-encoded type-section indices; branches carry a loop's params / a
    block's results)
  - the **full** integer set with spec-correct traps: divide-by-zero and
    `INT_MIN/−1` trap, `INT_MIN rem −1` is 0; signed **and** unsigned
    `div`/`rem`/`shr`/compares, `rotl`/`rotr`, `clz`/`ctz`/`popcnt`,
    sign-extension ops, i32 results wrapped to 32 bits
  - `call` / `call_indirect` (the latter with the runtime **signature check**)
  - **linear memory**: all sized loads/stores, `memory.size`/`memory.grow`
    (declared max + wasm32 limit honoured, −1 past them), **bulk memory**
    (`memory.copy`/`fill`/`init` with up-front bounds checks, `data.drop`,
    passive data segments), active data segments applied at instantiation
  - **globals**, **tables** + reference types: `table.get/set/grow/size/`
    `fill/copy/init`, `elem.drop`, `ref.null`/`ref.is_null`/`ref.func`,
    typed `select`; all element-segment encodings (active/passive/declared,
    index- and expression-form)
  - **floats** — full f32/f64 arithmetic and conversions with IEEE-correct
    semantics: NaN-aware comparisons (`ne` true on unordered), canonical-NaN
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
    deterministically

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
