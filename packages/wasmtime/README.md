# wasmtime — a WebAssembly runtime in pure NURL

A from-scratch WebAssembly runtime written entirely in NURL — no libwasm, no
embedded interpreter, no external `wasmtime` binary. It decodes a wasm module
and executes its bytecode directly.

The motivation: NURL already compiles to `wasm32-wasi`, and packages like
[`swarm-mcp`](../swarm-mcp) ship compute kernels as wasm. Today those workers
shell out to the reference `wasmtime`. A pure-NURL runtime removes that external
dependency — a worker (or any NURL program) can host a wasm module itself.

This is a **multi-milestone** effort. This first release is the **integer
core**, cross-checked against the reference wasmtime.

## What works now

```sh
wasmtime run --invoke <export> <module.wasm> [int args…]
```

- **Decoder** (`src/module.nu`) — magic/version, LEB128 (signed + unsigned), and
  the type / function / export / code sections. Unknown sections are skipped.
- **Interpreter** (`src/interp.nu`) — a stack machine over 64-bit integer cells:
  - structured control flow: `block`, `loop`, `if`/`else`, `br`, `br_if`,
    `return`, `end` (an explicit control stack; matching `end`/`else` found by a
    one-pass immediate scan)
  - `i32`/`i64` `const`, full integer arithmetic / comparison / bitwise ops
    (`add` … `shr_s`, `eq` … `ge_s`, `eqz`), with i32 results wrapped to 32 bits
  - `local.get/set/tee`, `drop`, `select`, `i32.wrap_i64`, `i64.extend_i32_*`
  - direct `call` (recursive frames; one shared value stack)
  - **linear memory**: `i32`/`i64` `load`/`store` incl. sized 8/16/32-bit
    signed/unsigned variants, `memory.size`/`memory.grow`, and the **data
    section** (active segments copied into memory at load time)
  - **globals** (`global.get`/`global.set`, const-initialised) and **tables**
    + **`call_indirect`** (element segments populate the function table)

```sh
# add(i32,i32) → i32
wasmtime run --invoke add  add.wasm 40 2          # → 42
# sumto(i64) → i64   (a loop: Σ 1..n)
wasmtime run --invoke sumto sum.wasm 100000       # → 5000050000
# max(i32,i32) → i32  (if/else)
wasmtime run --invoke max  max.wasm 3 9           # → 9
```

The test suite (`tests/interp_test.nu`) runs hand-encoded modules whose expected
results were produced by the reference `wasmtime` — so the NURL runtime is
verified against the real thing, and is ASan-clean.

## Roadmap

The integer core is the foundation; hosting real `wasm32-wasi` programs (such as
the swarm-mcp kernels) needs, roughly in order:

1. ~~**Linear memory** + `i32`/`i64` load/store (and `memory.size`/`grow`), plus
   the data section.~~ **Done.**
2. ~~**Globals**, **tables** + `call_indirect`.~~ **Done.**
3. **Floats** (`f32`/`f64`) and the numeric conversions.
4. **Imports + the WASI surface**, starting with **`--dir`**: `proc_exit`,
   `fd_write` (stdout), `args_*`, `environ_*`, and the preopened-directory file
   ops (`path_open`, `fd_read`, `fd_write`, `fd_seek`, `fd_close`). With `--dir`
   a module gets one host directory and nothing else — the minimal capability.

When the WASI layer lands, `swarm-mcp` workers can drop the external `wasmtime`
dependency and run kernels on this runtime.

## Layout

```
src/module.nu   wasm binary decoder: byte cursor, LEB128, sections, the module model
src/interp.nu   the stack-machine interpreter: control flow + integer ops
src/main.nu     CLI: load a module, invoke an export with integer args, print the result
```

## Tests

```sh
NURL_STDLIB=<repo> ../../nurl.sh tests/interp_test.nu /tmp/it && /tmp/it
```

## License

MIT OR Apache-2.0.
