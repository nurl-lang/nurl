# Changelog

## [2.1.0] — 2026-10-07

The JIT gets a second, optimizing tier, and the fuzzer that now reaches it
found three places where every engine disagreed with the specification.
The CLI and the library API are unchanged.

### Added

- **Tier 8: a register-allocating JIT** (`src/rjit.nu`), on by default on
  x86-64 wherever the template JIT runs (guard-page memory, or no memory at
  all). It lowers the same predecoded records as the template tier, but
  with their slot liveness solved, each slot's independent values split
  into webs, and those webs given registers by a linear scan that spills by
  use density: 12 GPRs and 14 xmm registers instead of a handful of pins
  over a memory frame. On top of that:
  - a register calling convention between tier-8 functions (up to five
    arguments in registers, the result in rax), frameless leaves, and
    direct `call rel32` links patched in as callees are compiled — all
    code lives in one address-space reservation so every link reaches;
  - integer division and remainder by a constant as shifts or a multiply
    by the reciprocal; `memory.copy` / `memory.fill` inline when in bounds;
  - a compare feeding the selects behind it, or a bit test / mask test
    feeding the branch behind it, as one flag-setting instruction;
  - BMI2 shifts and lzcnt/tzcnt on x86-64-v3 CPUs.
  `NURL_NWASM_RJIT=0` keeps the template tier; `NURL_NWASM_BMI2=0` keeps
  tier 8 on baseline x86-64; `NURL_NWASM_RJIT_DBG=1` reports a function
  tier 8 declined (and why) or compiled but could not install;
  `NURL_NWASM_RJIT_TRACE=<fidx>` prints a function's webs and where they
  went; `NURL_NWASM_PERFMAP=1` writes `/tmp/perf-<pid>.map` for `perf`.
- `tests/divconst_diff.sh`: every div/rem opcode against ~45 constant
  divisors per width, all engines against the reference wasmtime.

### Fixed

- `i32.reinterpret_f32` left the f32's bits zero-extended in the slot, in
  every engine. Every i32 a slot holds is sign-extended — the predecoder
  drops `i64.extend_i32_s` on the strength of it — so a negative pattern
  reinterpreted and widened came out positive. `f32.reinterpret_i32` now
  zero-extends, matching every other f32 slot.
- Declared `externref` / `funcref` locals started out 0 instead of null,
  in every engine, so `ref.is_null` of a fresh local was false.
- The template JIT's overflow stub returned without the result in rax.
- The fuzz harness (`tests/fuzz_diff.sh`) also runs the template tier, and
  skips exports whose names a CLI would read as an option.

## [2.0.0] — 2026-10-03

Nothing is released by hand any more: `Module` and `Interp` free themselves.
The `nwasm` CLI (`nwasm run …`, its flags, output and exit codes) is
unchanged; the major version is for the embedding library API below.

### Changed (breaking)

- `module_decode` returns a `Module` and `interp_new` an `Interp` — library
  handles over an rcbox (NURL's `stdlib/core/rcbox.nu`) instead of `*Module` /
  `*Interp` pointers (`: *Module m ( module_decode b )` →
  `: Module m ( module_decode b )`). Every function that took the pointer
  (`interp_*`, `exec_func`, `module_export_func`, `module_export_global`,
  `module_func_name`, `module_func_type`) takes the handle. Every copy (a
  struct field, a `Vec` element, `Module_share` / `Interp_share`) is the same
  module or instance, and the last owner releases it: the section records,
  the linear memory and its guard reservation, predecoded and JIT-compiled
  bodies, open guest sockets, and the instance's threads (joined first).
  `module_free` / `interp_free` are optional early releases.
- Fields are no longer reachable through the handle; read them through the
  new accessors `module_ok`, `module_err`, `module_num_import_funcs`,
  `interp_stack` (push an invoked export's arguments, read its results),
  `interp_trapmsg`, `interp_exit_code`, `interp_set_fuel`.
- `module_decode` takes its byte vector as a `sink` (it always kept it as the
  module image; now the signature says so).
- The byte cursor `Wc` is a plain value (`: ~ Wc c ( wc_new bytes )`, and the
  `wc_*` readers take it `inout`) instead of a `*Wc` heap block; `wc_free`
  has nothing left to do.
- `interp_thread_new` is removed from the public API (wasi-threads spawn their
  instance internally).

### Fixed

- An `Interp` holds a share of its `Module`, so the module can no longer be
  released under a live instance.
- A spawned wasi-thread's instance starts zeroed (its memory base selector and
  JIT state were read uninitialised), and its start closure is no longer kept
  in a hand-freed holder — the runtime runs the thread on its own copy.

### Performance

- Instruction counts (`perf stat -e instructions:u`, JIT and interpreter, the
  bench corpus plus nurlc.wasm compiling json_parse.nu) are unchanged to
  −0.1 %.

Requires NURL 0.69.0.

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
