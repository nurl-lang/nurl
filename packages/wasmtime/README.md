# wasmtime — a WebAssembly runtime in pure NURL

A from-scratch WebAssembly runtime written entirely in NURL — no libwasm, no
embedded interpreter, no external `wasmtime` binary. It decodes a wasm module
and executes its bytecode directly.

The motivation: NURL already compiles to `wasm32-wasi`, and packages like
[`swarm-mcp`](../swarm-mcp) ship compute kernels as wasm. Today those workers
shell out to the reference `wasmtime`. A pure-NURL runtime removes that external
dependency — a worker (or any NURL program) can host a wasm module itself.

This is a **multi-milestone** effort. The runtime now decodes and executes the
full integer + float instruction set **and hosts real `wasm32-wasi` command
modules** — a clang- or NURL-compiled `hello.wasm` prints to stdout and exits
through this runtime, with output and exit code matching the reference wasmtime.

## What works now

```sh
# WASI command mode: run a wasm32-wasi module's _start (argv = module + args)
wasmtime run hello.wasm                            # → hello from wasm

# Direct mode: invoke an exported function with integer / float args
wasmtime run --invoke <export> <module.wasm> [args…]
```

- **Decoder** (`src/module.nu`) — magic/version, LEB128 (signed + unsigned), and
  the type / function / export / code sections. Unknown sections are skipped.
- **Interpreter** (`src/interp.nu`) — a stack machine over 64-bit integer cells:
  - structured control flow: `block`, `loop`, `if`/`else`, `br`, `br_if`,
    `return`, `end` (an explicit control stack; matching `end`/`else` found by a
    one-pass immediate scan)
  - `i32`/`i64` `const`, the **full** integer arithmetic / comparison / bitwise
    set: signed **and** unsigned `div`/`rem`/`shr`/compares, `rotl`/`rotr`,
    `clz`/`ctz`/`popcnt`, sign-extension ops, with i32 results wrapped to 32 bits
  - `local.get/set/tee`, `drop`, `select`, `i32.wrap_i64`, `i64.extend_i32_*`
  - direct `call` (recursive frames; one shared value stack)
  - **linear memory**: `i32`/`i64` `load`/`store` incl. sized 8/16/32-bit
    signed/unsigned variants, `memory.size`/`memory.grow`, **bulk memory**
    (`memory.copy`/`memory.fill`), and the **data section** (active segments
    copied into memory at load time)
  - **globals** (`global.get`/`global.set`, const-initialised) and **tables**
    + **`call_indirect`** (element segments populate the function table)
  - **floats** — `f32`/`f64` `const`/`load`/`store`, arithmetic (`add` … `div`,
    `min`/`max`/`copysign`), `sqrt`/`abs`/`neg`/`ceil`/`floor`/`trunc`/`nearest`,
    comparisons, and every int↔float conversion (`trunc`/`convert`/`demote`/
    `promote`/`reinterpret`). Held as IEEE-754 bits via `std/floatbits`.
  - **imports + WASI** (`wasi_snapshot_preview1`): `proc_exit`, `fd_write`
    (stdout/stderr, iovec walk), `args_*`, `environ_*`, `clock_time_get`,
    `random_get`, and a real **file-descriptor table**.
  - **`--dir` preopen + file ops**: one host directory is exposed to the module
    (`fd_prestat_*`), and `path_open` / `fd_read` / `fd_seek` / `fd_write` (to a
    buffer flushed on `fd_close`) / `fd_filestat_get` back real files under it —
    enough for a program to read a source file. Cross-checked against reference
    wasmtime on multi-kilobyte reads.

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
compile NURL. This runtime is ready for that: it loads the 562 KB
`nurlc.wasm` (built via `./buildwasm.sh`), runs its startup path (prints
`usage:` with no args), and — when compiling a file — reaches **the exact same
`unreachable` trap as the reference `wasmtime`**. That trap is a defect in
`nurlc.wasm`'s own codegen (the NURL→wasm 32-bit-pointer ABI: pointer values the
compiler treats as 64-bit get mangled on wasm, steering a `match` to an
uncovered arm), not a gap in this runtime. Simpler NURL→wasm programs (e.g.
`cat.wasm`) run correctly end-to-end. Closing the self-hosting loop needs that
compiler-side ABI fix; the runtime side is in place.

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
