# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-07-27T12:22:26Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `9111299b88a23cbb25425c2c91c305a29f59fac5` |
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
| _(floor: empty program)_ | _1.510_ | _10.570_ | _7.0_ | _1.708_ | _8.232_ | _4.8_ | _1.515_ | _19.302_ | _12.7_ |
| `lcg` | 41.183 | 63.348 | 1.5 | 32.909 | 61.315 | 1.9 | 36.185 | 55.044 | 1.5 |
| `affine_mix` | 40.523 | 61.405 | 1.5 | 41.117 | 66.680 | 1.6 | 40.623 | 54.937 | 1.4 |
| `packet_classifier` | 70.215 | 78.930 | 1.1 | 69.073 | 80.049 | 1.2 | 67.798 | 69.127 | 1.0 |
| `ring_write` | 41.292 | 79.389 | 1.9 | 43.946 | 77.009 | 1.8 | 43.901 | 64.662 | 1.5 |
| `histogram_bins` | 42.732 | 71.423 | 1.7 | 42.018 | 74.914 | 1.8 | 41.307 | 64.209 | 1.6 |
| `prefix_scan` | 21.309 | 49.506 | 2.3 | 18.372 | 56.206 | 3.1 | 24.808 | 31.197 | 1.3 |
| `binary_search` | 33.155 | 105.340 | 3.2 | 36.373 | 116.769 | 3.2 | 41.671 | 97.377 | 2.3 |
| `sort_window` | 49.554 | 86.902 | 1.8 | 52.290 | 73.854 | 1.4 | 53.553 | 126.604 | 2.4 |
| `bloom_filter` | 19.152 | 48.000 | 2.5 | 18.007 | 51.440 | 2.9 | 17.037 | 35.199 | 2.1 |
| `hash_join` | 6.134 | 31.054 | 5.1 | 6.490 | 33.094 | 5.1 | 6.628 | 25.039 | 3.8 |
| `sieve` | 42.894 | 67.377 | 1.6 | 42.528 | 64.524 | 1.5 | 42.194 | 60.775 | 1.4 |
| `fib` | 33.745 | 70.521 | 2.1 | 34.790 | 65.328 | 1.9 | 33.466 | 63.047 | 1.9 |
| `collatz` | 18.066 | 42.776 | 2.4 | 18.866 | 40.755 | 2.2 | 17.400 | 39.977 | 2.3 |
| `matmul` | 35.267 | 64.453 | 1.8 | 36.260 | 58.969 | 1.6 | 34.066 | 55.368 | 1.6 |
| `json_parse` | 12.571 | 51.354 | 4.1 | 11.904 | 37.642 | 3.2 | 15.011 | 40.701 | 2.7 |

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
| `lcg` | 1.3 | — | 1.7 | 1.0 |
| `affine_mix` | 1.3 | — | 1.5 | 0.9 |
| `packet_classifier` | 1.0 | — | 1.1 | 0.8 |
| `ring_write` | 1.7 | — | 1.6 | 1.1 |
| `histogram_bins` | 1.5 | — | 1.7 | 1.1 |
| `prefix_scan` | 2.0 | — | 2.9 | — |
| `binary_search` | 3.0 | 2.3 | 3.1 | 1.9 |
| `sort_window` | 1.6 | — | 1.3 | 2.1 |
| `bloom_filter` | 2.1 | — | 2.7 | — |
| `hash_join` | 4.4 | — | 5.2 | — |
| `sieve` | 1.4 | — | 1.4 | 1.0 |
| `fib` | 1.9 | — | 1.7 | 1.4 |
| `collatz` | 1.9 | — | 1.9 | 1.3 |
| `matmul` | 1.6 | — | 1.5 | 1.1 |
| `json_parse` | 3.7 | — | 2.9 | 1.6 |

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
| _(floor: empty program)_ | _49.586_ | _4.7_ | _32.8_ | _SKIPPED_ | _SKIPPED_ |
| `lcg` | 2551.115 | 40.3 | 61.9 | SKIPPED | SKIPPED |
| `affine_mix` | 5236.536 | 85.3 | 129.2 | SKIPPED | SKIPPED |
| `packet_classifier` | 5609.458 | 71.1 | 79.9 | SKIPPED | SKIPPED |
| `ring_write` | 6964.832 | 87.7 | 168.7 | SKIPPED | SKIPPED |
| `histogram_bins` | 7687.511 | 107.6 | 179.9 | SKIPPED | SKIPPED |
| `prefix_scan` | 2514.534 | 50.8 | 118.0 | SKIPPED | SKIPPED |
| `binary_search` | 14824.405 | 140.7 | 447.1 | SKIPPED | SKIPPED |
| `sort_window` | 40168.675 | 462.2 | 810.6 | SKIPPED | SKIPPED |
| `bloom_filter` | 3837.375 | 79.9 | 200.4 | SKIPPED | SKIPPED |
| `hash_join` | 3264.882 | 105.1 | 532.3 | SKIPPED | SKIPPED |
| `sieve` | 5110.445 | 75.8 | 119.1 | SKIPPED | SKIPPED |
| `fib` | 11376.658 | 161.3 | 337.1 | SKIPPED | SKIPPED |
| `collatz` | 2645.571 | 61.8 | 146.4 | SKIPPED | SKIPPED |
| `matmul` | 4192.871 | 65.1 | 118.9 | SKIPPED | SKIPPED |
| `json_parse` | 29149.574 | 567.6 | 2318.8 | SKIPPED | SKIPPED |

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
| `lcg` | 16 | 819 | 16 | 686 | 3743 | 1733 |
| `affine_mix` | 16 | 819 | 16 | 686 | 3743 | 1734 |
| `packet_classifier` | 16 | 819 | 16 | 686 | 3743 | 1734 |
| `ring_write` | 16 | 819 | 16 | 686 | 3743 | 1734 |
| `histogram_bins` | 16 | 819 | 16 | 686 | 3743 | 1734 |
| `prefix_scan` | 16 | 820 | 16 | 687 | 3743 | 1734 |
| `binary_search` | 16 | 819 | 16 | 687 | 3743 | 1735 |
| `sort_window` | 16 | 820 | 16 | 687 | 3743 | 1734 |
| `bloom_filter` | 16 | 820 | 16 | 687 | 3743 | 1734 |
| `hash_join` | 20 | 821 | 16 | 695 | 3743 | 1736 |
| `sieve` | 16 | 819 | 16 | 691 | 3742 | 1733 |
| `fib` | 16 | 819 | 16 | 686 | 3738 | 1733 |
| `collatz` | 16 | 819 | 16 | 686 | 3738 | 1733 |
| `matmul` | 16 | 820 | 16 | 691 | 3743 | 1734 |
| `json_parse` | 34 | 849 | 16 | 736 | 3757 | 1763 |

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
| _(floor: empty program)_ | _798_ | _1063_ | _+33 %_ | _10.570_ | _60.276_ | _+470 %_ |
| `lcg` | 819 | 1064 | +30 % | 63.348 | 90.273 | +43 % |
| `affine_mix` | 819 | 1064 | +30 % | 61.405 | 95.278 | +55 % |
| `packet_classifier` | 819 | 1064 | +30 % | 78.930 | 112.320 | +42 % |
| `ring_write` | 819 | 1064 | +30 % | 79.389 | 99.169 | +25 % |
| `histogram_bins` | 819 | 1064 | +30 % | 71.423 | 104.321 | +46 % |
| `prefix_scan` | 820 | 1064 | +30 % | 49.506 | 78.566 | +59 % |
| `binary_search` | 819 | 1064 | +30 % | 105.340 | 133.505 | +27 % |
| `sort_window` | 820 | 1064 | +30 % | 86.902 | 113.051 | +30 % |
| `bloom_filter` | 820 | 1064 | +30 % | 48.000 | 80.531 | +68 % |
| `hash_join` | 821 | 1067 | +30 % | 31.054 | 67.468 | +117 % |
| `sieve` | 819 | 1064 | +30 % | 67.377 | 99.631 | +48 % |
| `fib` | 819 | 1064 | +30 % | 70.521 | 100.020 | +42 % |
| `collatz` | 819 | 1064 | +30 % | 42.776 | 77.469 | +81 % |
| `matmul` | 820 | 1064 | +30 % | 64.453 | 92.486 | +43 % |
| `json_parse` | 849 | 1119 | +32 % | 51.354 | 86.472 | +68 % |

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
| _(floor: empty program)_ | _3.080_ | _100.137_ | _1344.016_ | _75.422_ | _582.966_ | _156.718_ | _102.580_ |
| `lcg` | 3.858 | 114.276 | 1382.076 | 87.007 | 959.991 | 178.911 | 117.602 |
| `affine_mix` | 3.493 | 115.152 | 1356.697 | 87.965 | 949.898 | 170.456 | 122.011 |
| `packet_classifier` | 3.473 | 112.784 | 1317.455 | 89.343 | 921.005 | 168.487 | 114.505 |
| `ring_write` | 3.394 | 112.196 | 1288.880 | 88.396 | 923.347 | 166.190 | 112.252 |
| `histogram_bins` | 4.284 | 112.554 | 1298.565 | 91.446 | 919.696 | 176.198 | 114.709 |
| `prefix_scan` | 4.437 | 116.553 | 1303.081 | 92.921 | 928.181 | 176.495 | 113.213 |
| `binary_search` | 4.875 | 118.572 | 1293.481 | 89.775 | 913.326 | 176.963 | 119.733 |
| `sort_window` | 3.885 | 119.865 | 1286.924 | 94.916 | 933.638 | 178.569 | 131.538 |
| `bloom_filter` | 6.264 | 123.713 | 1303.167 | 93.007 | 921.550 | 173.527 | 124.198 |
| `hash_join` | 11.743 | 247.889 | 1292.096 | 141.570 | 964.115 | 224.254 | 165.530 |
| `sieve` | 4.461 | 116.452 | 1289.724 | 99.464 | 916.268 | 179.714 | 122.395 |
| `fib` | 3.826 | 104.812 | 1284.927 | 85.011 | 910.366 | 164.787 | 109.382 |
| `collatz` | 4.465 | 114.138 | 1296.565 | 89.066 | 907.583 | 172.090 | 115.567 |
| `matmul` | 5.611 | 124.134 | 1299.104 | 101.733 | 923.450 | 217.474 | 150.153 |
| `json_parse` | 84.447 | 832.449 | 1490.903 | 144.127 | 1061.113 | 314.274 | 225.747 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `affine_mix` | `227901546981696845` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `2814341850483607168` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |

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
