# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-07T20:25:13Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `9ae4f77d97d9ee1cfb00c182dbe9da75a5228664` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37681146671 |
| NURL | `v0.70.0-36-g9ae4f77d` |
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
| C/Rust on the NURL interpreter | no (add --nwasm-all-langs) |
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
| _(floor: empty program)_ | _1.459_ | _10.342_ | _7.1_ | _1.490_ | _5.978_ | _4.0_ | _1.656_ | _36.020_ | _21.8_ |
| `lcg` | 39.112 | 65.324 | 1.7 | 39.147 | 65.861 | 1.7 | 39.162 | 73.262 | 1.9 |
| `packet_classifier` | 56.350 | 78.716 | 1.4 | 56.188 | 77.866 | 1.4 | 56.260 | 84.602 | 1.5 |
| `ring_write` | 42.077 | 79.007 | 1.9 | 42.216 | 78.116 | 1.9 | 42.297 | 83.986 | 2.0 |
| `histogram_bins` | 39.534 | 82.745 | 2.1 | 41.174 | 75.955 | 1.8 | 39.254 | 82.652 | 2.1 |
| `prefix_scan` | 21.625 | 38.162 | 1.8 | 21.729 | 39.935 | 1.8 | 21.882 | 45.307 | 2.1 |
| `binary_search` | 38.031 | 85.781 | 2.3 | 38.227 | 96.721 | 2.5 | 44.491 | 101.736 | 2.3 |
| `sort_window` | 27.355 | 67.599 | 2.5 | 27.256 | 58.669 | 2.2 | 26.807 | 65.392 | 2.4 |
| `bloom_filter` | 15.375 | 44.193 | 2.9 | 18.106 | 45.525 | 2.5 | 18.404 | 51.899 | 2.8 |
| `hash_join` | 27.986 | 81.079 | 2.9 | 30.123 | 73.160 | 2.4 | 29.683 | 80.262 | 2.7 |
| `sieve` | 17.961 | 67.803 | 3.8 | 17.999 | 59.707 | 3.3 | 18.188 | 57.289 | 3.1 |
| `fib` | 25.277 | 69.019 | 2.7 | 29.888 | 70.430 | 2.4 | 30.103 | 74.690 | 2.5 |
| `collatz` | 12.258 | 45.708 | 3.7 | 12.263 | 46.066 | 3.8 | 12.411 | 50.452 | 4.1 |
| `matmul` | 33.547 | 56.656 | 1.7 | 33.422 | 50.147 | 1.5 | 33.753 | 62.184 | 1.8 |
| `json_parse` | 9.328 | 57.111 | 6.1 | 8.668 | 38.482 | 4.4 | 11.640 | 59.558 | 5.1 |
| `nbody` | 40.577 | 76.587 | 1.9 | 40.665 | 69.373 | 1.7 | 38.823 | 80.090 | 2.1 |

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
| `lcg` | 1.5 | — | 1.6 | 1.0 |
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.7 | — | 1.8 | 1.2 |
| `histogram_bins` | 1.9 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.4 | — | 1.7 | — |
| `binary_search` | 2.1 | — | 2.5 | 1.5 |
| `sort_window` | 2.2 | — | 2.0 | — |
| `bloom_filter` | 2.4 | — | 2.4 | — |
| `hash_join` | 2.7 | — | 2.3 | 1.6 |
| `sieve` | 3.5 | — | 3.3 | — |
| `fib` | 2.5 | — | 2.3 | 1.4 |
| `collatz` | 3.3 | — | 3.7 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 5.9 | — | 4.5 | — |
| `nbody` | 1.7 | — | 1.6 | 1.2 |

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
| _(floor: empty program)_ | _10.342_ | _**3.280**_ | _5.978_ | _SKIPPED_ | _36.020_ | _SKIPPED_ |
| `lcg` | 65.324 | **42.438** | 65.861 | SKIPPED | 73.262 | SKIPPED |
| `packet_classifier` | 78.716 | **51.944** | 77.866 | SKIPPED | 84.602 | SKIPPED |
| `ring_write` | 79.007 | **49.665** | 78.116 | SKIPPED | 83.986 | SKIPPED |
| `histogram_bins` | 82.745 | **44.591** | 75.955 | SKIPPED | 82.652 | SKIPPED |
| `prefix_scan` | 38.162 | **12.279** | 39.935 | SKIPPED | 45.307 | SKIPPED |
| `binary_search` | 85.781 | **53.325** | 96.721 | SKIPPED | 101.736 | SKIPPED |
| `sort_window` | 67.599 | **50.795** | 58.669 | SKIPPED | 65.392 | SKIPPED |
| `bloom_filter` | 44.193 | **18.335** | 45.525 | SKIPPED | 51.899 | SKIPPED |
| `hash_join` | 81.079 | **44.663** | 73.160 | SKIPPED | 80.262 | SKIPPED |
| `sieve` | 67.803 | **30.222** | 59.707 | SKIPPED | 57.289 | SKIPPED |
| `fib` | 69.019 | **50.700** | 70.430 | SKIPPED | 74.690 | SKIPPED |
| `collatz` | 45.708 | **22.659** | 46.066 | SKIPPED | 50.452 | SKIPPED |
| `matmul` | 56.656 | **32.529** | 50.147 | SKIPPED | 62.184 | SKIPPED |
| `json_parse` | 57.111 | **35.388** | 38.482 | SKIPPED | 59.558 | SKIPPED |
| `nbody` | 76.587 | **49.655** | 69.373 | SKIPPED | 80.090 | SKIPPED |

`nwasm` is faster than the reference runtime on 15 of 15 NURL modules,
— C modules and — Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.280_ | _0.3_ | _2.2_ | _—_ | _—_ |
| `lcg` | 42.438 | 0.6 | 1.1 | — | — |
| `packet_classifier` | 51.944 | 0.7 | 0.9 | — | — |
| `ring_write` | 49.665 | 0.6 | 1.2 | — | — |
| `histogram_bins` | 44.591 | 0.5 | 1.1 | — | — |
| `prefix_scan` | 12.279 | 0.3 | 0.6 | — | — |
| `binary_search` | 53.325 | 0.6 | 1.4 | — | — |
| `sort_window` | 50.795 | 0.8 | 1.9 | — | — |
| `bloom_filter` | 18.335 | 0.4 | 1.2 | — | — |
| `hash_join` | 44.663 | 0.6 | 1.6 | — | — |
| `sieve` | 30.222 | 0.4 | 1.7 | — | — |
| `fib` | 50.700 | 0.7 | 2.0 | — | — |
| `collatz` | 22.659 | 0.5 | 1.8 | — | — |
| `matmul` | 32.529 | 0.6 | 1.0 | — | — |
| `json_parse` | 35.388 | 0.6 | 3.8 | — | — |
| `nbody` | 49.655 | 0.6 | 1.2 | — | — |

The C and Rust `nwasm` cells are `SKIPPED`: they are the cross-frontend
control — modules this runtime never saw during development, from two
other LLVM frontends — and running them costs about three times the
whole rest of the suite, so they are opt-in. `--nwasm-all-langs` fills
them in. Until it is run, this section says what the interpreter does
with NURL output and nothing about whether it is tuned for it.

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
| _(floor: empty program)_ | _4_ | _311_ | _+7715 %_ | _10.342_ | _147.386_ | _+1325 %_ |
| `lcg` | 26 | 311 | +1087 % | 65.324 | 183.238 | +181 % |
| `packet_classifier` | 26 | 311 | +1090 % | 78.716 | 195.447 | +148 % |
| `ring_write` | 26 | 311 | +1087 % | 79.007 | 195.591 | +148 % |
| `histogram_bins` | 26 | 311 | +1084 % | 82.745 | 198.644 | +140 % |
| `prefix_scan` | 27 | 311 | +1071 % | 38.162 | 155.658 | +308 % |
| `binary_search` | 26 | 311 | +1082 % | 85.781 | 206.910 | +141 % |
| `sort_window` | 27 | 312 | +1073 % | 67.599 | 189.796 | +181 % |
| `bloom_filter` | 26 | 312 | +1078 % | 44.193 | 166.339 | +276 % |
| `hash_join` | 28 | 314 | +1009 % | 81.079 | 189.112 | +133 % |
| `sieve` | 26 | 311 | +1087 % | 67.803 | 179.871 | +165 % |
| `fib` | 26 | 311 | +1090 % | 69.019 | 190.997 | +177 % |
| `collatz` | 26 | 311 | +1091 % | 45.708 | 165.409 | +262 % |
| `matmul` | 26 | 311 | +1076 % | 56.656 | 177.159 | +213 % |
| `json_parse` | 50 | 331 | +561 % | 57.111 | 171.537 | +200 % |
| `nbody` | 28 | 313 | +1016 % | 76.587 | 192.127 | +151 % |

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
| _(floor: empty program)_ | _3.497_ | _99.927_ | _49.205_ | _55.749_ | _40.919_ | _64.604_ | _74.000_ |
| `lcg` | 3.817 | 119.740 | 49.537 | 66.486 | 41.953 | 67.054 | 85.623 |
| `packet_classifier` | 3.713 | 115.733 | 50.318 | 68.400 | 40.232 | 68.101 | 80.011 |
| `ring_write` | 3.996 | 117.772 | 51.582 | 66.609 | 40.435 | 68.891 | 81.499 |
| `histogram_bins` | 4.110 | 123.945 | 51.830 | 69.310 | 43.201 | 71.896 | 84.470 |
| `prefix_scan` | 4.162 | 123.569 | 56.452 | 71.811 | 41.834 | 71.346 | 84.894 |
| `binary_search` | 4.657 | 122.963 | 52.538 | 72.571 | 41.483 | 78.256 | 86.297 |
| `sort_window` | 4.624 | 132.233 | 55.058 | 77.531 | 41.623 | 78.810 | 96.355 |
| `bloom_filter` | 5.039 | 130.632 | 55.606 | 79.302 | 41.982 | 77.294 | 89.055 |
| `hash_join` | 9.192 | 254.235 | 68.962 | 120.754 | 41.452 | 115.073 | 122.254 |
| `sieve` | 4.713 | 131.499 | 51.911 | 77.747 | 40.350 | 80.959 | 89.920 |
| `fib` | 3.867 | 114.554 | 51.927 | 64.203 | 41.275 | 73.137 | 81.217 |
| `collatz` | 4.032 | 121.578 | 54.414 | 70.380 | 41.885 | 69.521 | 81.641 |
| `matmul` | 5.782 | 131.607 | 55.020 | 79.328 | 40.975 | 88.531 | 98.333 |
| `json_parse` | 47.160 | 664.517 | 151.346 | 122.942 | 41.206 | 179.878 | 150.562 |
| `nbody` | 6.828 | 140.610 | 64.292 | 94.239 | 43.710 | 91.378 | 103.704 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `6152419568754618368` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595260366167553674` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |

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
