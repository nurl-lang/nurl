# Changelog

## Unreleased

Nothing is released by hand any more: `Module` and `Interp` free themselves.

- `module_decode` returns a `Module` and `interp_new` an `Interp` — library
  handles over an rcbox (NURL's `stdlib/core/rcbox.nu`) instead of `*Module` /
  `*Interp` pointers. Every copy (a struct field, a `Vec` element,
  `Module_share` / `Interp_share`) is the same module or instance, and the
  last owner releases it: the section records, the linear memory and its
  guard reservation, predecoded and JIT-compiled bodies, open guest sockets,
  and the instance's threads (joined first). `module_free` / `interp_free` are
  optional early releases.
- An `Interp` holds a share of its `Module`, so the module can no longer be
  released under a live instance.
- `module_decode` takes its byte vector as a `sink` (it always kept it as the
  module image; now the signature says so).
- Fields are read through accessors: `module_ok`, `module_err`,
  `module_num_import_funcs`, `interp_stack` (push an invoked export's
  arguments, read its results), `interp_trapmsg`, `interp_exit_code`,
  `interp_set_fuel`.
- The byte cursor `Wc` is a plain value (`: ~ Wc c ( wc_new bytes )`, passed
  `inout`) instead of a heap block; `wc_free` has nothing left to do.
- A spawned wasi-thread's instance starts zeroed (its memory base selector and
  JIT state were read uninitialised), and its start closure is no longer kept
  in a hand-freed holder — the runtime runs the thread on its own copy.

Instruction counts (`perf stat -e instructions:u`, JIT and interpreter, the
bench corpus plus nurlc.wasm compiling json_parse.nu) are unchanged to −0.1 %.

## 1.0.11

The interpreter keeps its own copy of a coroutine's closure environment and drops it with `nurl_closure_drop` (NURL 0.67.0 closure ownership, #1141).

## 1.0.10

`--version` reported 1.0.8 while the manifest said 1.0.9.

The string is a literal in the source and nothing derives it from `nurl.toml`,
so the bump to 1.0.9 moved one and not the other. A published version cannot be
replaced, only superseded — which is what this is.

## 1.0.9

`interp_free`, `module_free`, `wc_free` and 4 more now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 1.0.8 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

It also carries the write-deadline and nonblocking socket declarations that
came with toolchain 0.65.0: absolute TCP/TLS write deadlines, prepared
nonblocking writes and reads, and combined read/write readiness.
