# Changelog

## [2.4.0] — 2026-10-09

### Changed

- **A call to `__multi3` runs as the multiply it is.** Core wasm has no
  64×64→128 multiply, so every wasm32 toolchain lowers a 128-bit product —
  C's `unsigned __int128`, Rust's `u128`, NURL's `nurl_umulhi` /
  `nurl_mac_*` — to a call of compiler-rt's `__multi3(ret, a_lo, a_hi, b_lo,
  b_hi)`, which rebuilds the product from four 32×32 multiplies and stores it
  through `ret`. That function was 52 % of a Poly1305 module's run time. The
  predecoder now recognises the two `__multi3` bodies the toolchains link
  (LLVM's compiler-rt — zig cc and NURL modules — and Rust's
  compiler-builtins) by their exact bytes and signature, never by name, and
  predecodes a direct call to either into three multiplies, two adds, a new
  multiply-high record (`mul` on x86-64, in every tier) and the body's two
  stores in the order the body makes them, so a trap on the second leaves
  memory as the body would. Anything else stays a call.

  | Module (bench/, cycles) | before | after |
  |---|---:|---:|
  | poly1305 C / Rust / NURL | 794M / 877M / 771M | 416M / 419M / 441M |
  | x25519 C / Rust / NURL | 1375M / 1447M / 1325M | 724M / 731M / 715M |

  Checked on every tier against the reference wasmtime: 6561 edge-value
  128×128 products and 2M random ones from C and Rust, out-of-bounds stores
  in both store orders, and `tests/fuzz_diff.sh`.

- **A spilled value is read from the register it was just stored from.**
  Tier 8 computes a spilled web's definition in rax and stores it to the
  web's frame home; the next record, reading that web, loaded it straight
  back — a store and a store-forwarded reload, four or five cycles, on
  every link of the dependency chain. ChaCha20 and BLAKE2b update sixteen
  state words in place, more than there are registers, so their quarter
  rounds were made of such links. When nothing at all has been emitted
  since that store, and no label lies between (a branch target or a
  forward jump's landing forgets it), a read of the slot — a load, or the
  memory operand of an ALU op or `imul` — now takes rax instead. The store
  stays for later readers.

  | Module (bench/, cycles) | before | after | wasmtime |
  |---|---:|---:|---:|
  | chacha20 C / Rust / NURL | 254M / 261M / 230M | 203M / 206M / 178M | 196M / 209M / 167M |
  | blake2b C / Rust / NURL | 447M / 521M / 284M | 394M / 478M / 243M | 347M / 444M / 216M |

  Every other bench module runs within noise of before, and all 60 print
  what they printed.

- **`while (n != 0)` on a 64-bit counter is one branch.** LLVM spells it
  `i64.eqz; i32.eqz; br_if`, and the inner eqz was a record of its own:
  tier 8 materialised its 0/1 with `setcc` for the branch behind to test
  again — five instructions where `add -1; jne` is two. The predecoder now
  rewrites an `i32.eqz` of the eqz it just emitted into `ne x, 0` against
  the constant pool's zero; the compare-and-branch fusion folds that into
  the branch, and into the add in front of it. Every C module of the
  corpus has a dozen such loops, and NURL's have more.

- **Loop-carried by a copy is not loop-carried by a computation.** Tier 8
  ranks a web some loop writes eight times denser for a register, since a
  spilled one puts a store and a reload on its loop-carried chain. A
  SHA-2 round rotates eight words, six of them by plain copies (h = g,
  g = f, …): a delay line, whose spilled store has the rest of the round
  before the read that waits on it. The ranking could not tell those from
  the two words the round computes, and the scan spilled a and e — the
  round's critical path, a store and a reload per round on each. A copy
  of the previous iteration's value of another web (through any chain of
  copies), of a value from before the loop or of a constant now earns the
  ×8 only when a read of its destination sits within four records of the
  write.

- **A pointer parameter is zero-extended once, at the entry.** A memory
  access through an i32 parameter zero-extended it into rax first, every
  time, because the parameter arrived sign-extended — and a store whose
  value was in rax then had to reload it. A parameter whose high half no
  consumer reads is now zero-extended by the entry instead (a 32-bit load
  from the argument window, or `mov r32, r32` on the register entry, past
  the slab check, so the interpreter fallback never sees it), its web
  counts as zero-extended, and every access indexes `[r11 + reg + off]` as
  it stands.

  The three together (bench/, cycles, the other modules within noise, all
  60 printing what they printed):

  | Module | before | after | wasmtime |
  |---|---:|---:|---:|
  | sha512 C / Rust | 302M / 300M | 260M / 293M | 241M / 287M |
  | blake2b C / Rust | 390M / 473M | 365M / 451M | 347M / 444M |
  | bloom_filter C / Rust | 5.37G / 5.18G | 4.96G / 4.83G | 5.23G / 5.32G |
  | poly1305 NURL | 428M | 399M | 829M |
  | hash_join Rust | 18.0G | 17.5G | 20.2G |

  `tests/semantics_test.nu` covers the double eqz as a loop branch on a
  counter whose low half is zero, as br_if, select, if and a value, with
  its inner 0/1 tee'd into a local, and pointer parameters with and
  without a reader of their high half. `tests/fuzz_diff.sh` (400 modules)
  is clean and the `nurlc.wasm` self-compile is byte-identical to the
  native compiler.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [2.3.1] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 2.3.0 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

## [2.3.0] — 2026-10-07

Tier 8's register allocation gets smarter about what it spills. Nothing
outside the JIT's output changed. Requires NURL 0.71.0: the functions
that work with raw pointers are declared `unsafe`, as 0.71.0 requires.

### Changed

- **A spilled value's reads take a free register where they can.** The
  linear scan keeps a value in one place for its whole live range, so a
  long-lived one the hot code reads stays in its frame slot once shorter,
  denser values fill the registers somewhere along it. After allocation,
  every run of its reads with no write between, no branch into it from
  outside, and a register no other value holds across it (calls leave only
  the callee-saved ones) loads the slot once and reads the register.
- **A value a loop writes holds its register before one it only reads.**
  Spilled, the first puts a store and a store-forwarded reload on its own
  loop-carried chain every iteration; the second only reloads, early.
- **A loop's records weigh once, whatever its back edges.** Each `continue`
  multiplied the spill weight of the code it spans by eight again.
- **A wrap of a value already zero-extended is a plain copy.**
- **An i32 argument is sign-extended where it is passed**, not where it is
  made: the predecoded call records carry which callee parameters are i32,
  so a value whose only full-width reader is a call — an index passed to a
  bounds-check panic on a cold path, as in every Rust slice access — no
  longer pays a `movsxd` in the hot loop.

Cycles at `--scale 100` against precompiled wasmtime on an i7-5930K:
hash_join 1.16 / 0.97 / 0.91 → 1.10 / 0.94 / 0.89 of wasmtime (NURL / C /
Rust), binary_search.rs 1.03 → 0.93, nbody.rs 1.11 → 1.05, json_parse.c
0.91 → 0.81.

### Fixed

- **i32 arguments through `call_indirect` arrived zero-extended** in tier 8
  (since 2.1.0) when nothing else read the value's high half: a callee that
  widened the parameter read 2147483648 for −2147483648. The template tier
  and the interpreter were right. `tests/semantics_test.nu` gains 14 checks
  on wrapped i32 arguments through every call path (324 in all).

## [2.2.0] — 2026-10-07

Tier 8 closes most of what was left between it and Cranelift on
register-heavy code. Nothing outside the JIT's output changed: the CLI,
the library API and every result are the same.

### Changed

- **i64 arithmetic whose high half nobody reads runs in 32 bits.** The
  analysis that lets an i32 result skip its sign extension now reaches
  through the i64 ops whose low half depends only on their operands' low
  halves (+ − × & | ^, shl, the fused pairs of them); an op whose readers
  take only the low half — a wrap, a narrow store, an and with a mask below
  2^32 — gets the 32-bit instruction, whose result is zero-extended for
  free. The 32-bit LCG every benchmark draws from loses its mask from the
  loop-carried chain.
- **Unsigned > and <= read the carry flag alone.** `a >u b` compiled to
  `cmp a, b` + `cmova` / `seta`, which read CF and ZF — two flag groups, an
  extra uop per cmov / setcc on Intel. The compare exchanges its operands
  (or tests `a >=u k + 1` against a constant) so the consumer is `cmovb` /
  `setae`.
- **r9 is allocatable where globals stay out of loops.** A function that
  touched any global reserved r9 as their base for its whole body; when no
  global access sits inside a loop, the base is loaded where used instead.
- **No slow lea.** An rbp / r13 base takes a displacement byte even for 0,
  and base + index + displacement is Intel's 3-cycle lea: unscaled, base and
  index swap; scaled, the base is copied into the destination first.
- **A zero-extended address indexes memory as it stands** — no
  `mov eax, r32` before `[r11 + rax]` when the address's web provably has a
  clear high half (32-bit ALU results, zero-extending loads, compares,
  non-negative constants, copies of those).
- **AVX three-operand scalar floats** (`vaddsd x, a, b`) on x86-64-v3, so a
  result in a register of its own needs no copy of its first operand. FMA
  stays out: one rounding instead of two would change wasm's results.
  `NURL_NWASM_BMI2=0` keeps SSE.
- **eqz and and-tests fuse into flags**: an eqz feeding selects hands them
  its flags; `and x, k` read only by an eqz becomes `test x, imm32` or
  `bt x, b`; an add-and-branch on `== 0` / `!= 0` uses the add's own ZF; the
  fused pairs start from their first operand's register (`imul r, s, imm`,
  `lea r, [s + t]`).

Cycles at `--scale 100` against precompiled wasmtime on an i7-5930K:
sort_window 1.25 / 1.28 / 1.19 → 1.03 / 1.06 / 1.07 of wasmtime (NURL /
C / Rust), ring_write 0.94 → 0.87, histogram_bins 0.93 → 0.77, collatz
1.50 → 0.97, packet_classifier 1.10 → 0.90.

### Added

- `tests/semantics_test.nu`: 85 checks on narrowed arithmetic and unsigned
  compares (310 in all), every expectation from wasmtime.

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
