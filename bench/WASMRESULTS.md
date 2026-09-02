# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-09-02T03:36:36Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `6f6d60a771a5c6f42d164e3abe20ec0890d30f7f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33587483258 |
| NURL | `v0.58.0-1-g6f6d60a7` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.1 (7bac2c277 2026-08-24)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.8 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
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
| _(floor: empty program)_ | _1.485_ | _10.505_ | _7.1_ | _1.561_ | _7.786_ | _5.0_ | _1.677_ | _33.352_ | _19.9_ |
| `lcg` | 41.116 | 66.599 | 1.6 | 41.273 | 67.922 | 1.6 | 41.282 | 76.634 | 1.9 |
| `packet_classifier` | 59.612 | 82.439 | 1.4 | 58.651 | 83.624 | 1.4 | 59.443 | 89.755 | 1.5 |
| `ring_write` | 43.848 | 80.484 | 1.8 | 44.295 | 81.036 | 1.8 | 43.753 | 89.735 | 2.1 |
| `histogram_bins` | 42.118 | 84.815 | 2.0 | 42.397 | 81.217 | 1.9 | 42.100 | 85.233 | 2.0 |
| `prefix_scan` | 22.668 | 37.223 | 1.6 | 23.067 | 37.580 | 1.6 | 23.179 | 45.495 | 2.0 |
| `binary_search` | 33.805 | 89.123 | 2.6 | 33.507 | 90.699 | 2.7 | 39.171 | 100.350 | 2.6 |
| `sort_window` | 29.396 | 68.365 | 2.3 | 29.072 | 62.050 | 2.1 | 28.512 | 67.624 | 2.4 |
| `bloom_filter` | 18.625 | 51.136 | 2.7 | 19.265 | 46.500 | 2.4 | 19.522 | 53.376 | 2.7 |
| `hash_join` | 27.780 | 71.654 | 2.6 | 29.217 | 69.982 | 2.4 | 29.556 | 80.216 | 2.7 |
| `sieve` | 19.019 | 66.173 | 3.5 | 18.657 | 63.648 | 3.4 | 19.177 | 57.383 | 3.0 |
| `fib` | 26.747 | 75.873 | 2.8 | 31.465 | 72.324 | 2.3 | 26.391 | 76.551 | 2.9 |
| `collatz` | 12.832 | 46.091 | 3.6 | 13.048 | 46.250 | 3.5 | 13.119 | 52.067 | 4.0 |
| `matmul` | 45.323 | 63.183 | 1.4 | 44.439 | 51.851 | 1.2 | 45.714 | 58.718 | 1.3 |
| `json_parse` | 8.073 | 47.698 | 5.9 | 8.698 | 38.235 | 4.4 | 11.600 | 56.192 | 4.8 |
| `nbody` | 43.870 | 72.596 | 1.7 | 43.856 | 70.376 | 1.6 | 41.685 | 80.942 | 1.9 |

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
| `lcg` | 1.4 | — | 1.5 | 1.1 |
| `packet_classifier` | 1.2 | — | 1.3 | 1.0 |
| `ring_write` | 1.7 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.8 | — | 1.8 | 1.3 |
| `prefix_scan` | 1.3 | — | 1.4 | — |
| `binary_search` | 2.4 | — | 2.6 | 1.8 |
| `sort_window` | 2.1 | — | 2.0 | 1.3 |
| `bloom_filter` | 2.4 | — | 2.2 | — |
| `hash_join` | 2.3 | — | 2.2 | 1.7 |
| `sieve` | 3.2 | — | 3.3 | — |
| `fib` | 2.6 | — | 2.2 | 1.7 |
| `collatz` | 3.1 | — | 3.3 | — |
| `matmul` | 1.2 | — | 1.0 | — |
| `json_parse` | 5.6 | — | 4.3 | — |
| `nbody` | 1.5 | — | 1.5 | 1.2 |

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

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C on `nwasm` | Rust on `nwasm` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.700_ | _0.3_ | _1.8_ | _2.612_ | _2.754_ |
| `lcg` | 42.867 | 0.6 | 1.0 | 44.496 | 44.843 |
| `packet_classifier` | 63.108 | 0.8 | 1.1 | 65.355 | 66.060 |
| `ring_write` | 57.904 | 0.7 | 1.3 | 58.109 | 58.728 |
| `histogram_bins` | 59.215 | 0.7 | 1.4 | 63.941 | 63.132 |
| `prefix_scan` | 13.433 | 0.4 | 0.6 | 16.306 | 13.954 |
| `binary_search` | 67.814 | 0.8 | 2.0 | 69.985 | 103.904 |
| `sort_window` | 75.601 | 1.1 | 2.6 | 59.331 | 64.782 |
| `bloom_filter` | 23.642 | 0.5 | 1.3 | 27.554 | 26.161 |
| `hash_join` | 60.398 | 0.8 | 2.2 | 69.311 | 64.042 |
| `sieve` | 39.266 | 0.6 | 2.1 | 41.856 | 37.590 |
| `fib` | 76.425 | 1.0 | 2.9 | 71.952 | 62.534 |
| `collatz` | 27.336 | 0.6 | 2.1 | 29.927 | 28.154 |
| `matmul` | 31.922 | 0.5 | 0.7 | 33.877 | 33.977 |
| `json_parse` | 47.582 | 1.0 | 5.9 | 20.092 | 95.279 |
| `nbody` | 89.158 | 1.2 | 2.0 | 73.503 | 91.317 |

The C and Rust columns are the control. They are modules this runtime
never saw during development, emitted by two other LLVM frontends; that
they run at all is a correctness result, and that they run at a similar
ratio says the interpreter has no NURL-shaped fast path.

## 4. Artefact size (KiB)

A wasm module carries its own copy of everything it links — wasi-libc,
the language runtime — where a native binary borrows the system one.
These are the bytes that have to be shipped, and (for the two runtimes
above) parsed before the program starts.

| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|
| `lcg` | 17 | 1106 | 16 | 915 | 4403 | 2084 |
| `packet_classifier` | 17 | 1106 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 17 | 1106 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 17 | 1106 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 17 | 1107 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 17 | 1106 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 17 | 1107 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 17 | 1107 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 25 | 1108 | 16 | 923 | 4406 | 2086 |
| `sieve` | 17 | 1106 | 16 | 916 | 4403 | 2084 |
| `fib` | 17 | 1106 | 16 | 915 | 4402 | 2083 |
| `collatz` | 17 | 1106 | 16 | 915 | 4402 | 2083 |
| `matmul` | 17 | 1107 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 35 | 1131 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 17 | 1108 | 16 | 919 | 4404 | 2085 |

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
| _(floor: empty program)_ | _1084_ | _1408_ | _+30 %_ | _10.505_ | _135.030_ | _+1185 %_ |
| `lcg` | 1106 | 1408 | +27 % | 66.599 | 173.464 | +160 % |
| `packet_classifier` | 1106 | 1408 | +27 % | 82.439 | 186.823 | +127 % |
| `ring_write` | 1106 | 1408 | +27 % | 80.484 | 188.669 | +134 % |
| `histogram_bins` | 1106 | 1408 | +27 % | 84.815 | 185.815 | +119 % |
| `prefix_scan` | 1107 | 1408 | +27 % | 37.223 | 141.333 | +280 % |
| `binary_search` | 1106 | 1408 | +27 % | 89.123 | 193.870 | +118 % |
| `sort_window` | 1107 | 1409 | +27 % | 68.365 | 179.384 | +162 % |
| `bloom_filter` | 1107 | 1409 | +27 % | 51.136 | 152.496 | +198 % |
| `hash_join` | 1108 | 1411 | +27 % | 71.654 | 176.587 | +146 % |
| `sieve` | 1106 | 1408 | +27 % | 66.173 | 159.744 | +141 % |
| `fib` | 1106 | 1408 | +27 % | 75.873 | 175.921 | +132 % |
| `collatz` | 1106 | 1408 | +27 % | 46.091 | 150.860 | +227 % |
| `matmul` | 1107 | 1408 | +27 % | 63.183 | 166.533 | +164 % |
| `json_parse` | 1131 | 1432 | +27 % | 47.698 | 155.152 | +225 % |
| `nbody` | 1108 | 1410 | +27 % | 72.596 | 180.834 | +149 % |

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
| _(floor: empty program)_ | _2.805_ | _102.042_ | _62.932_ | _63.223_ | _56.150_ | _68.026_ | _77.854_ |
| `lcg` | 3.000 | 119.587 | 61.561 | 73.483 | 44.301 | 74.788 | 84.830 |
| `packet_classifier` | 3.155 | 121.738 | 63.602 | 75.396 | 44.325 | 75.168 | 110.386 |
| `ring_write` | 3.179 | 120.597 | 63.034 | 74.991 | 44.876 | 75.555 | 86.830 |
| `histogram_bins` | 3.326 | 125.181 | 65.086 | 77.172 | 45.177 | 77.651 | 89.419 |
| `prefix_scan` | 3.332 | 123.461 | 63.231 | 79.323 | 43.813 | 78.259 | 87.505 |
| `binary_search` | 3.411 | 122.640 | 65.331 | 73.989 | 44.088 | 80.435 | 90.250 |
| `sort_window` | 3.529 | 127.568 | 65.858 | 79.753 | 45.113 | 84.890 | 108.635 |
| `bloom_filter` | 3.763 | 126.917 | 64.765 | 79.895 | 45.112 | 81.508 | 90.565 |
| `hash_join` | 6.130 | 231.465 | 73.051 | 118.094 | 43.388 | 114.823 | 128.614 |
| `sieve` | 3.360 | 123.347 | 64.283 | 82.120 | 45.161 | 86.621 | 94.511 |
| `fib` | 3.084 | 115.951 | 64.008 | 70.932 | 44.090 | 72.012 | 83.524 |
| `collatz` | 3.172 | 117.820 | 62.728 | 73.840 | 44.443 | 75.413 | 87.436 |
| `matmul` | 3.614 | 126.330 | 64.862 | 82.906 | 44.065 | 99.346 | 101.065 |
| `json_parse` | 52.154 | 576.132 | 151.905 | 121.678 | 46.485 | 180.879 | 163.384 |
| `nbody` | 4.856 | 137.673 | 74.109 | 98.680 | 45.114 | 99.283 | 109.469 |

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
