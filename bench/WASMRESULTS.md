# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-07-27T09:53:03Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Host | `Linux x86_64` |
| Kernel | `Linux 7.0.0-28-generic x86_64` |
| CPU | Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (12 logical cores) |
| Memory | 32770952 KiB |
| Commit | `ad7e4391c17af5bc82ffc997b8e97005329aabd2` |
| NURL | `v0.26.0-15-gad7e439` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.82.0 (f6e511eec 2024-10-15) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.1.3), built from this repo |
| C → wasm | `zig 0.13.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 44.0.0 (af382d7d9 2026-04-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.6.2 (pure NURL)) — interpreter, built from this repo |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 900 s |
| C/Rust on the NURL interpreter | no (add --wt-all-langs) |
| Reference runtime cache | **off** (`-C cache=n`) — every cell is decode + compile + run |

## 1. What wasm costs — native vs the same module on a JIT

Whole-process wall clock in milliseconds, start-up included. The `x`
columns are wasm ÷ native for that language: how much slower the *same
source* got by being compiled to wasm and run under a JIT instead of
straight to the machine. Because all three languages appear, the column
answers a question a NURL-only table could not: whether a gap belongs to
NURL's wasm pipeline or to wasm itself.

| Benchmark | NURL native | NURL wasm | x | C native | C wasm | x | Rust native | Rust wasm | x |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.664_ | _62.536_ | _37.6_ | _1.527_ | _7.151_ | _4.7_ | _1.705_ | _17.188_ | _10.1_ |
| `lcg` | 39.454 | 92.613 | 2.3 | 36.734 | 70.561 | 1.9 | 40.684 | 55.154 | 1.4 |
| `affine_mix` | 33.592 | 91.026 | 2.7 | 34.469 | 59.458 | 1.7 | 40.279 | 53.595 | 1.3 |
| `packet_classifier` | 63.118 | 111.411 | 1.8 | 68.643 | 77.651 | 1.1 | 68.195 | 69.459 | 1.0 |
| `ring_write` | 37.471 | 98.644 | 2.6 | 37.305 | 69.063 | 1.9 | 43.807 | 64.403 | 1.5 |
| `histogram_bins` | 41.374 | 100.163 | 2.4 | 41.853 | 73.794 | 1.8 | 41.801 | 64.298 | 1.5 |
| `prefix_scan` | 24.097 | 79.843 | 3.3 | 24.841 | 48.479 | 2.0 | 24.624 | 29.781 | 1.2 |
| `binary_search` | 34.228 | 132.185 | 3.9 | 36.161 | 117.260 | 3.2 | 43.948 | 99.095 | 2.3 |
| `sort_window` | 41.188 | 110.110 | 2.7 | 52.501 | 75.914 | 1.4 | 53.575 | 123.660 | 2.3 |
| `bloom_filter` | 18.133 | 81.014 | 4.5 | 16.750 | 45.560 | 2.7 | 17.689 | 36.494 | 2.1 |
| `hash_join` | 6.320 | 66.795 | 10.6 | 4.886 | 31.750 | 6.5 | 5.320 | 24.550 | 4.6 |
| `sieve` | 43.446 | 99.869 | 2.3 | 42.302 | 68.849 | 1.6 | 37.415 | 61.224 | 1.6 |
| `fib` | 34.440 | 102.493 | 3.0 | 33.702 | 65.008 | 1.9 | 30.222 | 64.897 | 2.1 |
| `collatz` | 18.651 | 78.851 | 4.2 | 17.458 | 43.512 | 2.5 | 18.617 | 38.712 | 2.1 |
| `matmul` | 35.631 | 89.686 | 2.5 | 35.353 | 60.555 | 1.7 | 35.041 | 55.030 | 1.6 |
| `json_parse` | 11.850 | 88.650 | 7.5 | 8.871 | 39.651 | 4.5 | 14.477 | 40.095 | 2.8 |

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
numbers carrying both their errors. That is not a rare edge case in the
**NURL x** column — a 1 MB module's compilation is comparable to the
benchmarks themselves, which is exactly why the `+gc` column beside it
exists: the same NURL programs linked with `--gc-sections` (section 5)
have a floor small enough to subtract cleanly, so they are where the
steady-state throughput of NURL's wasm can actually be read.

| Benchmark | NURL x | NURL +gc x | C x | Rust x |
|---|---:|---:|---:|---:|
| `lcg` | — | 1.3 | 1.8 | 1.0 |
| `affine_mix` | — | 1.5 | 1.6 | 0.9 |
| `packet_classifier` | — | 1.1 | 1.1 | 0.8 |
| `ring_write` | — | 1.6 | 1.7 | 1.1 |
| `histogram_bins` | — | 1.7 | 1.7 | 1.2 |
| `prefix_scan` | — | 1.8 | 1.8 | — |
| `binary_search` | 2.1 | 2.9 | 3.2 | 1.9 |
| `sort_window` | — | 1.8 | 1.3 | 2.1 |
| `bloom_filter` | — | 2.0 | 2.5 | 1.2 |
| `hash_join` | — | 4.4 | 7.3 | — |
| `sieve` | — | 1.3 | 1.5 | 1.2 |
| `fib` | — | 1.9 | 1.8 | 1.7 |
| `collatz` | — | 2.0 | 2.3 | 1.3 |
| `matmul` | — | 1.5 | 1.6 | 1.1 |
| `json_parse` | — | 3.6 | 4.4 | 1.8 |

## 3. The pure-NURL runtime (`packages/wasmtime`)

The identical modules from section 1, executed by an interpreter written
in NURL instead of by a JIT written in Rust. `vs JIT` is the cost of the
runtime; `vs native` is the end-to-end cost of choosing this way to ship.
Losing orders of magnitude to a JIT is the shape an interpreter has; the
point of the column is that the size of the gap is measured rather than
assumed, per benchmark, so it can be aimed at.

Read the floor row first, because it goes the other way: on a program
that does nothing the interpreter *beats* the JIT. Nothing surprising is
happening — the JIT compiles the whole module before `_start`, and the
interpreter only decodes it and walks the handful of instructions that
run. That crossover is the honest answer to "which runtime should I
use": it depends entirely on how long the guest runs.

| Benchmark | NURL on `wt` | vs JIT | vs native | C on `wt` | Rust on `wt` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _45.100_ | _0.7_ | _27.1_ | _SKIPPED_ | _SKIPPED_ |
| `lcg` | 2561.128 | 27.7 | 64.9 | SKIPPED | SKIPPED |
| `affine_mix` | 5261.156 | 57.8 | 156.6 | SKIPPED | SKIPPED |
| `packet_classifier` | 5645.706 | 50.7 | 89.4 | SKIPPED | SKIPPED |
| `ring_write` | 7022.937 | 71.2 | 187.4 | SKIPPED | SKIPPED |
| `histogram_bins` | 7289.204 | 72.8 | 176.2 | SKIPPED | SKIPPED |
| `prefix_scan` | 2512.158 | 31.5 | 104.3 | SKIPPED | SKIPPED |
| `binary_search` | 15085.611 | 114.1 | 440.7 | SKIPPED | SKIPPED |
| `sort_window` | 40323.696 | 366.2 | 979.0 | SKIPPED | SKIPPED |
| `bloom_filter` | 3820.273 | 47.2 | 210.7 | SKIPPED | SKIPPED |
| `hash_join` | 3324.280 | 49.8 | 526.0 | SKIPPED | SKIPPED |
| `sieve` | 5165.420 | 51.7 | 118.9 | SKIPPED | SKIPPED |
| `fib` | 11474.997 | 112.0 | 333.2 | SKIPPED | SKIPPED |
| `collatz` | 2662.316 | 33.8 | 142.7 | SKIPPED | SKIPPED |
| `matmul` | 4240.486 | 47.3 | 119.0 | SKIPPED | SKIPPED |
| `json_parse` | 29424.539 | 331.9 | 2483.1 | SKIPPED | SKIPPED |

The C and Rust columns are `SKIPPED`: they are the cross-frontend
control — modules this runtime never saw during development, from two
other LLVM frontends — and running them costs about three times the
whole rest of the suite, so they are opt-in. `--wt-all-langs` fills
them in. Until it is run, this section says what the interpreter does
with NURL output and nothing about whether it is tuned for it.

## 4. Artefact size (KiB)

A wasm module carries its own copy of everything it links — wasi-libc,
the language runtime — where a native binary borrows the system one.
These are the bytes that have to be shipped, and (for the two runtimes
above) parsed before the program starts.

| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|
| `lcg` | 16 | 1064 | 16 | 686 | 3743 | 1733 |
| `affine_mix` | 16 | 1064 | 16 | 686 | 3743 | 1734 |
| `packet_classifier` | 16 | 1064 | 16 | 686 | 3743 | 1734 |
| `ring_write` | 16 | 1064 | 16 | 686 | 3743 | 1734 |
| `histogram_bins` | 16 | 1064 | 16 | 686 | 3743 | 1734 |
| `prefix_scan` | 16 | 1064 | 16 | 687 | 3743 | 1734 |
| `binary_search` | 16 | 1064 | 16 | 687 | 3743 | 1735 |
| `sort_window` | 16 | 1064 | 16 | 687 | 3743 | 1734 |
| `bloom_filter` | 16 | 1064 | 16 | 687 | 3743 | 1734 |
| `hash_join` | 20 | 1067 | 16 | 695 | 3743 | 1736 |
| `sieve` | 16 | 1064 | 16 | 691 | 3742 | 1733 |
| `fib` | 16 | 1063 | 16 | 686 | 3738 | 1733 |
| `collatz` | 16 | 1064 | 16 | 686 | 3738 | 1733 |
| `matmul` | 16 | 1064 | 16 | 691 | 3743 | 1734 |
| `json_parse` | 34 | 1119 | 16 | 736 | 3757 | 1763 |

## 5. Dead code — what `--gc-sections` costs and buys

Every NURL module above was linked with `-Wl,--no-gc-sections`, the
default `wasmbuilder` ships. NURL closures store **function-table indices**
and section GC renumbers that table, so a closure captured before the
collection can call the wrong function after it — a run-time
`call_indirect` trap with no link error to warn anyone. The cost of that
default is that most of the NURL runtime ships in, and is translated by
the runtime, in every module that never calls it.

These rows are the same benchmarks rebuilt with `--gc-sections`, run on
the reference runtime, and held to the same output — none of them uses a
closure, so the hazard does not apply and the saving is measurable.

| Benchmark | Size | Size +gc | Δ | JIT | JIT +gc | Δ |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1063_ | _798_ | _−25 %_ | _62.536_ | _10.267_ | _−84 %_ |
| `lcg` | 1064 | 819 | −23 % | 92.613 | 60.884 | −34 % |
| `affine_mix` | 1064 | 819 | −23 % | 91.026 | 59.683 | −34 % |
| `packet_classifier` | 1064 | 819 | −23 % | 111.411 | 79.172 | −29 % |
| `ring_write` | 1064 | 819 | −23 % | 98.644 | 68.821 | −30 % |
| `histogram_bins` | 1064 | 819 | −23 % | 100.163 | 77.872 | −22 % |
| `prefix_scan` | 1064 | 820 | −23 % | 79.843 | 49.952 | −37 % |
| `binary_search` | 1064 | 820 | −23 % | 132.185 | 104.771 | −21 % |
| `sort_window` | 1064 | 820 | −23 % | 110.110 | 80.610 | −27 % |
| `bloom_filter` | 1064 | 820 | −23 % | 81.014 | 42.536 | −47 % |
| `hash_join` | 1067 | 821 | −23 % | 66.795 | 30.637 | −54 % |
| `sieve` | 1064 | 819 | −23 % | 99.869 | 66.558 | −33 % |
| `fib` | 1063 | 819 | −23 % | 102.493 | 71.491 | −30 % |
| `collatz` | 1064 | 819 | −23 % | 78.851 | 44.133 | −44 % |
| `matmul` | 1064 | 820 | −23 % | 89.686 | 60.514 | −33 % |
| `json_parse` | 1119 | 849 | −24 % | 88.650 | 47.099 | −47 % |

The saving is almost all fixed cost, so it is largest where the benchmark
itself is smallest — compare each row against the floor. It is reported
on the JIT and not on the interpreter because the interpreter is
execution-bound, not decode-bound: its floor row in section 3 is a few
tens of milliseconds against cells in the tens of *seconds*, so shrinking
the module cannot move it. This is a real optimisation, and what stands
between it and being the default is making closure function-table indices
survive renumbering — not the linker flag.

## 6. Compile time (median, ms)

The NURL wasm build is `wasmbuilder`: `nurlc` emits host LLVM IR, the IR
rewriter retargets it for `wasm32-wasi`, and the toolchain-bundled
`zig cc` links it against wasi-libc and a cached `runtime.wasm.o`. The
column is the whole pipeline, comparable to the NURL native total beside
it and to the C and Rust wasm columns.

| Benchmark | NURL `nurlc` | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.968_ | _109.052_ | _1334.094_ | _81.312_ | _602.986_ | _156.370_ | _109.577_ |
| `lcg` | 3.911 | 110.031 | 1362.946 | 95.402 | 951.330 | 183.458 | 123.338 |
| `affine_mix` | 4.045 | 110.049 | 1305.744 | 86.817 | 938.474 | 168.551 | 121.083 |
| `packet_classifier` | 3.792 | 109.116 | 1317.276 | 94.783 | 915.998 | 176.435 | 121.980 |
| `ring_write` | 3.754 | 106.551 | 1286.930 | 89.003 | 940.199 | 171.690 | 113.975 |
| `histogram_bins` | 4.750 | 117.854 | 1297.838 | 87.753 | 924.073 | 168.438 | 112.015 |
| `prefix_scan` | 4.434 | 113.783 | 1293.032 | 87.699 | 921.444 | 166.301 | 111.517 |
| `binary_search` | 3.848 | 111.293 | 1301.846 | 90.424 | 913.416 | 179.118 | 125.883 |
| `sort_window` | 4.458 | 123.809 | 1379.428 | 92.877 | 944.488 | 176.587 | 131.672 |
| `bloom_filter` | 5.249 | 118.834 | 1296.963 | 96.674 | 916.469 | 178.571 | 119.138 |
| `hash_join` | 9.265 | 246.170 | 1307.893 | 141.155 | 967.105 | 232.732 | 177.676 |
| `sieve` | 5.235 | 119.781 | 1358.393 | 94.151 | 938.741 | 186.617 | 131.672 |
| `fib` | 3.771 | 111.500 | 1337.662 | 87.876 | 938.591 | 171.183 | 114.812 |
| `collatz` | 4.219 | 107.542 | 1326.105 | 89.276 | 929.486 | 170.377 | 123.266 |
| `matmul` | 5.588 | 123.111 | 1337.730 | 99.820 | 950.490 | 213.000 | 153.248 |
| `json_parse` | 85.653 | 849.593 | 1560.415 | 141.863 | 1102.307 | 322.235 | 235.882 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `affine_mix` | `227901546981696845` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `hash_join` | `2814341850483607168` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--gc-sections` |

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
