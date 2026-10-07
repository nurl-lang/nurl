# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-07T20:58:17Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
the next run overwrites it. The machine-readable form of this same run
is [`results/wasm-latest.json`](results/wasm-latest.json).

This is the sibling of [`RESULTS.md`](RESULTS.md): same corpus, same
protocol, one axis rotated. `RESULTS.md` asks how fast NURL is against
four other languages; this file asks what **targeting wasm** costs, and
what running that wasm on **NURL's own runtime** costs. Every benchmark
is compiled to a native binary *and* a `wasm32-wasi` module in three
languages, and each module is run on two runtimes — ten timed cells per
row, all gated on printing the same line (section 7).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `48bf46ba7c253cd3c0e2f481d08adeac839ad8e5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37685529105 |
| NURL | `v0.70.0-38-g48bf46ba` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.2), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.3.0 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Workload scale | ×1 — the published contract (`--scale N` multiplies it) |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 900 s |
| C/Rust on the NURL interpreter | yes |
| Reference runtime cache | **off** (`-C cache=n`) — every cell is decode + compile + run |
| `nwasm` build | `NURL_SPLIT=0` — `nurl.sh` otherwise lowers a large program as one module per core, and ThinLTO cannot import every callee back across a part boundary. `nwasm` is the subject of section 3, and the reference runtime it is measured against is a release build; a split `nwasm` measured 5.0% slower over this corpus. |

## 1. What wasm costs — native vs the same module on a JIT

Whole-process wall clock in milliseconds, start-up included. The `x`
columns are wasm ÷ native for that language: how much slower the *same
source* got by being compiled to wasm and run under a JIT instead of
straight to the machine. Because all three languages appear, the column
answers a question a NURL-only table could not: whether a gap belongs to
NURL's wasm pipeline or to wasm itself.

| Benchmark | NURL native | NURL wasm | x | C native | C wasm | x | Rust native | Rust wasm | x |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.602_ | _11.077_ | _6.9_ | _1.606_ | _7.114_ | _4.4_ | _1.754_ | _32.924_ | _18.8_ |
| `lcg` | 44.175 | 70.419 | 1.6 | 44.195 | 71.089 | 1.6 | 44.266 | 76.775 | 1.7 |
| `packet_classifier` | 63.431 | 85.839 | 1.4 | 63.556 | 85.299 | 1.3 | 63.642 | 91.967 | 1.4 |
| `ring_write` | 47.583 | 85.994 | 1.8 | 47.743 | 85.647 | 1.8 | 47.775 | 89.801 | 1.9 |
| `histogram_bins` | 44.588 | 89.955 | 2.0 | 44.679 | 84.163 | 1.9 | 44.858 | 88.160 | 2.0 |
| `prefix_scan` | 24.423 | 38.833 | 1.6 | 24.430 | 38.831 | 1.6 | 24.632 | 46.642 | 1.9 |
| `binary_search` | 35.912 | 91.227 | 2.5 | 35.788 | 97.401 | 2.7 | 47.204 | 102.147 | 2.2 |
| `sort_window` | 30.649 | 70.227 | 2.3 | 30.718 | 63.916 | 2.1 | 30.153 | 69.124 | 2.3 |
| `bloom_filter` | 17.293 | 47.134 | 2.7 | 20.388 | 47.947 | 2.4 | 20.626 | 51.310 | 2.5 |
| `hash_join` | 29.149 | 67.272 | 2.3 | 30.550 | 74.925 | 2.5 | 31.123 | 79.943 | 2.6 |
| `sieve` | 20.620 | 62.513 | 3.0 | 20.096 | 59.935 | 3.0 | 20.239 | 56.039 | 2.8 |
| `fib` | 27.962 | 73.073 | 2.6 | 33.314 | 73.729 | 2.2 | 33.502 | 77.606 | 2.3 |
| `collatz` | 13.676 | 48.314 | 3.5 | 13.721 | 48.098 | 3.5 | 13.886 | 54.635 | 3.9 |
| `matmul` | 46.049 | 62.525 | 1.4 | 45.917 | 56.487 | 1.2 | 46.413 | 64.276 | 1.4 |
| `json_parse` | 9.094 | 55.770 | 6.1 | 8.795 | 39.170 | 4.5 | 12.002 | 57.513 | 4.8 |
| `nbody` | 46.010 | 73.608 | 1.6 | 46.154 | 73.756 | 1.6 | 43.926 | 84.244 | 1.9 |

The floor row matters more here than in `RESULTS.md`. A wasm cell pays
for the runtime compiling the whole module before `_start` runs, and a
NURL module links the entire NURL runtime whatever the program does — so
even the empty program is a ~1 MB module to JIT. Section 2 subtracts that
floor from both ends to show the steady-state ratio.

## 2. The same ratios, with start-up subtracted

Cell minus the floor of its own column, wasm ÷ native. This is the
number to quote for a long-running program, where module compilation is
amortised to nothing; section 1 is the number to quote for a short one,
where it is most of the run.

A `—` means the subtraction has no signal left in it: the floor is more
than half of that cell, so the remainder is a difference of two similar
numbers carrying both their errors. The `no gc` column is the
pre-0.1.4 default relinked with `--no-gc-sections` (section 5); its
floor is big enough that most of its rows land there, which is one of
the reasons it is no longer the default.

| Benchmark | NURL x | NURL no-gc x | C x | Rust x |
|---|---:|---:|---:|---:|
| `lcg` | 1.4 | — | 1.5 | 1.0 |
| `packet_classifier` | 1.2 | — | 1.3 | 1.0 |
| `ring_write` | 1.6 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.8 | — | 1.8 | 1.3 |
| `prefix_scan` | 1.2 | — | 1.4 | — |
| `binary_search` | 2.3 | — | 2.6 | 1.5 |
| `sort_window` | 2.0 | — | 2.0 | 1.3 |
| `bloom_filter` | 2.3 | — | 2.2 | — |
| `hash_join` | 2.0 | — | 2.3 | 1.6 |
| `sieve` | 2.7 | — | 2.9 | — |
| `fib` | 2.4 | — | 2.1 | 1.4 |
| `collatz` | 3.1 | — | 3.4 | — |
| `matmul` | 1.2 | — | 1.1 | — |
| `json_parse` | 6.0 | — | 4.5 | — |
| `nbody` | 1.4 | — | 1.5 | 1.2 |

## 3. The pure-NURL runtime (`packages/nwasm`)

The identical modules from section 1, executed by a runtime written in
NURL instead of in Rust: a register-record interpreter with a template
JIT on top (on by default; `NURL_NWASM_JIT=0` keeps the pure interpreter,
and metered or shared-memory runs fall back to it on their own).
`vs JIT` is the cost of the runtime; `vs native` is the end-to-end
cost of choosing this way to ship. The size of the gap is measured
rather than assumed, per benchmark, so it can be aimed at.

Read the floor row first, because it goes the other way: on a program
that does nothing this runtime *beats* the reference. Nothing surprising
is happening — the reference compiles the whole module before `_start`,
and `nwasm` only decodes it, compiling nothing but what runs. That
crossover is the honest answer to "which runtime should I use": it
depends entirely on how long the guest runs.

Both runtimes side by side first: whole-process wall clock in
milliseconds, each language's module on the reference runtime and on
`nwasm`. The fastest of the six cells in a row is in **bold**.

| Benchmark | NURL on `wasmtime` | NURL on `nwasm` | C on `wasmtime` | C on `nwasm` | Rust on `wasmtime` | Rust on `nwasm` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _11.077_ | _3.607_ | _7.114_ | _**3.099**_ | _32.924_ | _3.567_ |
| `lcg` | 70.419 | **47.219** | 71.089 | 51.381 | 76.775 | 50.783 |
| `packet_classifier` | 85.839 | **57.902** | 85.299 | 62.284 | 91.967 | 61.811 |
| `ring_write` | 85.994 | **54.706** | 85.647 | 58.481 | 89.801 | 57.860 |
| `histogram_bins` | 89.955 | **49.402** | 84.163 | 54.516 | 88.160 | 52.748 |
| `prefix_scan` | 38.833 | **12.397** | 38.831 | 18.938 | 46.642 | 17.570 |
| `binary_search` | 91.227 | **56.870** | 97.401 | 61.737 | 102.147 | 66.016 |
| `sort_window` | 70.227 | 50.826 | 63.916 | 49.895 | 69.124 | **47.428** |
| `bloom_filter` | 47.134 | **19.525** | 47.947 | 25.746 | 51.310 | 24.574 |
| `hash_join` | 67.272 | **45.571** | 74.925 | 49.379 | 79.943 | 49.356 |
| `sieve` | 62.513 | 33.682 | 59.935 | 37.945 | 56.039 | **30.165** |
| `fib` | 73.073 | 43.933 | 73.729 | 44.066 | 77.606 | **38.988** |
| `collatz` | 48.314 | **24.758** | 48.098 | 28.567 | 54.635 | 27.705 |
| `matmul` | 62.525 | 38.533 | 56.487 | 38.298 | 64.276 | **34.957** |
| `json_parse` | 55.770 | 31.567 | 39.170 | **20.978** | 57.513 | 27.580 |
| `nbody` | 73.608 | 58.986 | 73.756 | **53.905** | 84.244 | 55.796 |

`nwasm` is faster than the reference runtime on 15 of 15 NURL modules,
15 of 15 C modules and 15 of 15 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.607_ | _0.3_ | _2.3_ | _0.4_ | _0.1_ |
| `lcg` | 47.219 | 0.7 | 1.1 | 0.7 | 0.7 |
| `packet_classifier` | 57.902 | 0.7 | 0.9 | 0.7 | 0.7 |
| `ring_write` | 54.706 | 0.6 | 1.1 | 0.7 | 0.6 |
| `histogram_bins` | 49.402 | 0.5 | 1.1 | 0.6 | 0.6 |
| `prefix_scan` | 12.397 | 0.3 | 0.5 | 0.5 | 0.4 |
| `binary_search` | 56.870 | 0.6 | 1.6 | 0.6 | 0.6 |
| `sort_window` | 50.826 | 0.7 | 1.7 | 0.8 | 0.7 |
| `bloom_filter` | 19.525 | 0.4 | 1.1 | 0.5 | 0.5 |
| `hash_join` | 45.571 | 0.7 | 1.6 | 0.7 | 0.6 |
| `sieve` | 33.682 | 0.5 | 1.6 | 0.6 | 0.5 |
| `fib` | 43.933 | 0.6 | 1.6 | 0.6 | 0.5 |
| `collatz` | 24.758 | 0.5 | 1.8 | 0.6 | 0.5 |
| `matmul` | 38.533 | 0.6 | 0.8 | 0.7 | 0.5 |
| `json_parse` | 31.567 | 0.6 | 3.5 | 0.5 | 0.5 |
| `nbody` | 58.986 | 0.8 | 1.3 | 0.7 | 0.7 |

The C and Rust columns are the control. They are modules this runtime
never saw during development, emitted by two other LLVM frontends; that
they run at all is a correctness result, and that they run at a similar
ratio says the interpreter has no NURL-shaped fast path.

## 4. Artefact size (KiB)

A wasm module carries its own copy of everything it links — wasi-libc,
the language runtime — where a native binary borrows the system one.
These are the bytes that have to be shipped, and (for the two runtimes
above) parsed before the program starts.

Read the wasm columns knowing what each toolchain ships by DEFAULT,
because that is what this table measures and the defaults differ.
Since wasmbuilder 0.3.0 the NURL column is stripped of debug info, which
is what `nurl.sh` has always done natively — the native columns beside it
carry no DWARF either, in any of the three languages. `zig cc` and
`rustc` keep theirs for wasm, and it dominates them: an unstripped NURL
module was 1,126,353 bytes for the empty program, of which 3,070 were
code. So the NURL wasm column is roughly code, and the C and Rust wasm
columns are roughly debug info. Strip all three and they land within a
factor of a few; that comparison is not run here because a benchmark of
shipped artefacts should report what each toolchain actually ships.
Module-load time is unaffected either way — a runtime skips custom
sections — so nothing in sections 1-3 moves with this.

| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|
| `lcg` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `packet_classifier` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `ring_write` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `histogram_bins` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `prefix_scan` | 17 | 27 | 16 | 916 | 4431 | 2129 |
| `binary_search` | 17 | 26 | 16 | 916 | 4432 | 2129 |
| `sort_window` | 17 | 27 | 16 | 917 | 4431 | 2129 |
| `bloom_filter` | 17 | 26 | 16 | 917 | 4431 | 2129 |
| `hash_join` | 25 | 28 | 16 | 923 | 4433 | 2131 |
| `sieve` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `fib` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `collatz` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `matmul` | 17 | 26 | 16 | 917 | 4431 | 2129 |
| `json_parse` | 41 | 50 | 16 | 1007 | 4445 | 2159 |
| `nbody` | 17 | 28 | 16 | 919 | 4432 | 2130 |

## 5. Dead code — what `--no-gc-sections` would cost

Every NURL module above was linked with `-Wl,--gc-sections`, the
`wasmbuilder` default since 0.1.4: the unreachable part of the NURL
runtime is dropped instead of shipped and JIT-translated for nothing.
The old default, `--no-gc-sections`, exists as an escape hatch for a
closure/table-renumbering hazard that no longer reproduces — a
`--gc-sections` `nurlc.wasm` self-compiles byte-identically under both
runtimes. These rows are the same benchmarks relinked with the escape
hatch, held to the same output, so its price stays a number: what you
pay in bytes and module-load time if you ever have to reach for it.

| Benchmark | Size | Size no-gc | Δ | JIT | JIT no-gc | Δ |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _4_ | _311_ | _+7715 %_ | _11.077_ | _146.679_ | _+1224 %_ |
| `lcg` | 26 | 311 | +1087 % | 70.419 | 182.998 | +160 % |
| `packet_classifier` | 26 | 311 | +1090 % | 85.839 | 201.190 | +134 % |
| `ring_write` | 26 | 311 | +1087 % | 85.994 | 197.680 | +130 % |
| `histogram_bins` | 26 | 311 | +1084 % | 89.955 | 195.677 | +118 % |
| `prefix_scan` | 27 | 311 | +1071 % | 38.833 | 151.893 | +291 % |
| `binary_search` | 26 | 311 | +1082 % | 91.227 | 212.226 | +133 % |
| `sort_window` | 27 | 312 | +1073 % | 70.227 | 191.098 | +172 % |
| `bloom_filter` | 26 | 312 | +1078 % | 47.134 | 168.242 | +257 % |
| `hash_join` | 28 | 314 | +1009 % | 67.272 | 185.401 | +176 % |
| `sieve` | 26 | 311 | +1087 % | 62.513 | 176.099 | +182 % |
| `fib` | 26 | 311 | +1090 % | 73.073 | 189.647 | +160 % |
| `collatz` | 26 | 311 | +1091 % | 48.314 | 162.093 | +235 % |
| `matmul` | 26 | 311 | +1076 % | 62.525 | 175.733 | +181 % |
| `json_parse` | 50 | 331 | +561 % | 55.770 | 181.030 | +225 % |
| `nbody` | 28 | 313 | +1016 % | 73.608 | 193.220 | +162 % |

The cost is almost all fixed, so it is largest where the benchmark
itself is smallest — compare each row against the floor. It is reported
on the JIT and not on the interpreter because the interpreter is
execution-bound, not decode-bound: its floor row in section 3 is a few
tens of milliseconds against cells in the tens of *seconds*, so module
size cannot move it either way.

## 6. Compile time (median, ms)

The NURL wasm build is `wasmbuilder`: `nurlc` emits host LLVM IR, the IR
rewriter retargets it for `wasm32-wasi`, and the toolchain-bundled
`zig cc` links it against wasi-libc and a cached `runtime.wasm.o`. The
column is the whole pipeline, comparable to the NURL native total beside
it and to the C and Rust wasm columns.

| Benchmark | NURL `nurlc` | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.830_ | _109.882_ | _54.055_ | _64.765_ | _45.482_ | _56.815_ | _71.124_ |
| `lcg` | 4.213 | 128.139 | 57.418 | 73.215 | 45.479 | 61.454 | 76.486 |
| `packet_classifier` | 4.205 | 130.637 | 55.501 | 74.817 | 45.765 | 63.344 | 77.614 |
| `ring_write` | 4.400 | 130.855 | 57.418 | 75.160 | 46.069 | 63.918 | 78.872 |
| `histogram_bins` | 4.527 | 133.317 | 57.008 | 77.237 | 45.839 | 65.615 | 80.282 |
| `prefix_scan` | 4.562 | 133.950 | 56.966 | 79.054 | 45.896 | 65.799 | 81.338 |
| `binary_search` | 4.868 | 134.352 | 57.219 | 75.162 | 46.387 | 67.901 | 82.402 |
| `sort_window` | 4.974 | 140.930 | 57.713 | 81.806 | 45.141 | 71.853 | 85.965 |
| `bloom_filter` | 5.434 | 140.173 | 61.915 | 81.841 | 45.192 | 68.713 | 83.002 |
| `hash_join` | 9.222 | 247.221 | 70.376 | 122.651 | 45.181 | 102.478 | 117.375 |
| `sieve` | 4.838 | 135.392 | 57.956 | 84.159 | 45.958 | 73.614 | 86.422 |
| `fib` | 4.311 | 127.605 | 55.199 | 73.425 | 45.692 | 62.202 | 77.227 |
| `collatz` | 4.484 | 132.052 | 56.836 | 74.455 | 45.821 | 62.500 | 77.594 |
| `matmul` | 6.046 | 139.324 | 59.295 | 85.523 | 45.807 | 82.428 | 94.556 |
| `json_parse` | 47.417 | 642.431 | 157.665 | 125.120 | 47.304 | 161.614 | 148.341 |
| `nbody` | 7.278 | 150.881 | 68.153 | 100.245 | 45.803 | 85.352 | 98.875 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `6152419568754618368` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595260366167553674` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

## 8. Reading the numbers

* Sections 1 and 3 are whole-process wall clock, so a cell near its
  column's floor is mostly start-up — and on wasm, start-up includes the
  runtime ingesting the module. Section 2 is where the steady-state
  throughput ratio lives.
* Every cell in a row computes the same thing, but not necessarily with
  the same machine code. LLVM optimises for wasm and for x86-64
  differently: wasm has no flags register, no `cmov`, and a JIT compiling
  at load time cannot spend the time an offline `-O2` does. A ratio above
  1 is that difference, not lost work.
* The three languages share a corpus but not a runtime. A NURL module
  carries NURL's allocator and string machinery; a Rust module carries
  Rust's; a C module carries almost nothing. Section 4 is that difference
  in bytes, and part of the floor row is the same difference in time.
* The reference runtime's compiled-module cache is off. Its CLI enables
  that cache by default, which would make a cell mean "Cranelift ran" or
  "Cranelift did not run" depending on what happened to be in
  `~/.cache/wasmtime` — including across the floor row, whose whole job is
  to be subtracted from the others. Off, both runtimes are measured doing
  the same work: read the module, translate it, run it. A deployment that
  keeps the cache (or precompiles with `wasmtime compile`) pays the floor
  once instead of every run — section 2 is the number that survives that.
* `json_parse` reads `bench/data.json`, so every wasm run gets a `--dir .`
  preopen. The other rows pay the same preopen cost and need nothing from
  it, which keeps the column internally comparable.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
