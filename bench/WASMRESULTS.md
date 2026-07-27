# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-07-27T16:16:58Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `ce949e53299c41227a0f2e5c5e7b4e961678f26e` |
| NURL | `v0.26.0-15-gad7e439` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.82.0 (f6e511eec 2024-10-15) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.1.3), built from this repo |
| C → wasm | `zig 0.13.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 44.0.0 (af382d7d9 2026-04-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.8.0 (pure NURL)) — interpreter, built from this repo |

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
| _(floor: empty program)_ | _1.466_ | _10.084_ | _6.9_ | _1.423_ | _7.483_ | _5.3_ | _1.738_ | _17.805_ | _10.2_ |
| `lcg` | 40.741 | 64.935 | 1.6 | 41.495 | 61.669 | 1.5 | 39.031 | 55.294 | 1.4 |
| `affine_mix` | 41.145 | 63.809 | 1.6 | 40.127 | 62.574 | 1.6 | 40.512 | 52.039 | 1.3 |
| `packet_classifier` | 68.941 | 85.855 | 1.2 | 68.311 | 75.744 | 1.1 | 64.937 | 67.969 | 1.0 |
| `ring_write` | 34.623 | 70.213 | 2.0 | 44.028 | 68.896 | 1.6 | 43.953 | 63.454 | 1.4 |
| `histogram_bins` | 34.115 | 78.903 | 2.3 | 41.586 | 70.983 | 1.7 | 41.857 | 65.932 | 1.6 |
| `prefix_scan` | 25.322 | 57.668 | 2.3 | 23.142 | 53.268 | 2.3 | 25.468 | 31.713 | 1.2 |
| `binary_search` | 36.090 | 105.456 | 2.9 | 35.359 | 118.517 | 3.4 | 47.302 | 99.769 | 2.1 |
| `sort_window` | 40.001 | 81.282 | 2.0 | 52.524 | 69.243 | 1.3 | 53.871 | 124.091 | 2.3 |
| `bloom_filter` | 18.635 | 44.341 | 2.4 | 17.926 | 44.125 | 2.5 | 17.322 | 34.878 | 2.0 |
| `hash_join` | 5.233 | 31.506 | 6.0 | 6.708 | 31.524 | 4.7 | 6.928 | 25.201 | 3.6 |
| `sieve` | 43.861 | 67.245 | 1.5 | 35.892 | 64.981 | 1.8 | 40.994 | 58.794 | 1.4 |
| `fib` | 33.806 | 67.523 | 2.0 | 29.396 | 68.158 | 2.3 | 33.839 | 64.516 | 1.9 |
| `collatz` | 18.896 | 43.044 | 2.3 | 17.386 | 39.913 | 2.3 | 17.300 | 37.969 | 2.2 |
| `matmul` | 34.535 | 62.481 | 1.8 | 34.168 | 60.661 | 1.8 | 35.330 | 55.982 | 1.6 |
| `json_parse` | 12.478 | 49.236 | 3.9 | 12.207 | 35.869 | 2.9 | 15.592 | 41.307 | 2.6 |

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
| `lcg` | 1.4 | — | 1.4 | 1.0 |
| `affine_mix` | 1.4 | — | 1.4 | 0.9 |
| `packet_classifier` | 1.1 | — | 1.0 | 0.8 |
| `ring_write` | 1.8 | — | 1.4 | 1.1 |
| `histogram_bins` | 2.1 | — | 1.6 | 1.2 |
| `prefix_scan` | 2.0 | — | 2.1 | — |
| `binary_search` | 2.8 | 2.1 | 3.3 | 1.8 |
| `sort_window` | 1.8 | — | 1.2 | 2.0 |
| `bloom_filter` | 2.0 | — | 2.2 | — |
| `hash_join` | 5.7 | — | 4.5 | — |
| `sieve` | 1.3 | — | 1.7 | 1.0 |
| `fib` | 1.8 | — | 2.2 | 1.5 |
| `collatz` | 1.9 | — | 2.0 | 1.3 |
| `matmul` | 1.6 | — | 1.6 | 1.1 |
| `json_parse` | 3.6 | — | 2.6 | 1.7 |

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
| _(floor: empty program)_ | _43.225_ | _4.3_ | _29.5_ | _SKIPPED_ | _SKIPPED_ |
| `lcg` | 929.732 | 14.3 | 22.8 | SKIPPED | SKIPPED |
| `affine_mix` | 1766.980 | 27.7 | 42.9 | SKIPPED | SKIPPED |
| `packet_classifier` | 2396.063 | 27.9 | 34.8 | SKIPPED | SKIPPED |
| `ring_write` | 2563.129 | 36.5 | 74.0 | SKIPPED | SKIPPED |
| `histogram_bins` | 2954.806 | 37.4 | 86.6 | SKIPPED | SKIPPED |
| `prefix_scan` | 796.593 | 13.8 | 31.5 | SKIPPED | SKIPPED |
| `binary_search` | 5285.868 | 50.1 | 146.5 | SKIPPED | SKIPPED |
| `sort_window` | 5833.669 | 71.8 | 145.8 | SKIPPED | SKIPPED |
| `bloom_filter` | 1572.393 | 35.5 | 84.4 | SKIPPED | SKIPPED |
| `hash_join` | 523.996 | 16.6 | 100.1 | SKIPPED | SKIPPED |
| `sieve` | 2085.060 | 31.0 | 47.5 | SKIPPED | SKIPPED |
| `fib` | 2277.931 | 33.7 | 67.4 | SKIPPED | SKIPPED |
| `collatz` | 985.616 | 22.9 | 52.2 | SKIPPED | SKIPPED |
| `matmul` | 1375.227 | 22.0 | 39.8 | SKIPPED | SKIPPED |
| `json_parse` | 1528.779 | 31.1 | 122.5 | SKIPPED | SKIPPED |

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
| _(floor: empty program)_ | _798_ | _1063_ | _+33 %_ | _10.084_ | _60.858_ | _+504 %_ |
| `lcg` | 819 | 1064 | +30 % | 64.935 | 90.465 | +39 % |
| `affine_mix` | 819 | 1064 | +30 % | 63.809 | 90.625 | +42 % |
| `packet_classifier` | 819 | 1064 | +30 % | 85.855 | 112.321 | +31 % |
| `ring_write` | 819 | 1064 | +30 % | 70.213 | 106.566 | +52 % |
| `histogram_bins` | 819 | 1064 | +30 % | 78.903 | 103.327 | +31 % |
| `prefix_scan` | 820 | 1064 | +30 % | 57.668 | 85.040 | +47 % |
| `binary_search` | 819 | 1064 | +30 % | 105.456 | 133.475 | +27 % |
| `sort_window` | 820 | 1064 | +30 % | 81.282 | 111.033 | +37 % |
| `bloom_filter` | 820 | 1064 | +30 % | 44.341 | 76.422 | +72 % |
| `hash_join` | 821 | 1067 | +30 % | 31.506 | 65.197 | +107 % |
| `sieve` | 819 | 1064 | +30 % | 67.245 | 97.003 | +44 % |
| `fib` | 819 | 1064 | +30 % | 67.523 | 96.878 | +43 % |
| `collatz` | 819 | 1064 | +30 % | 43.044 | 71.325 | +66 % |
| `matmul` | 820 | 1064 | +30 % | 62.481 | 88.838 | +42 % |
| `json_parse` | 849 | 1119 | +32 % | 49.236 | 84.373 | +71 % |

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
| _(floor: empty program)_ | _3.796_ | _105.569_ | _1310.576_ | _75.921_ | _584.691_ | _152.129_ | _107.295_ |
| `lcg` | 3.510 | 108.710 | 1313.458 | 81.912 | 929.864 | 172.753 | 115.354 |
| `affine_mix` | 3.663 | 111.528 | 1313.913 | 89.004 | 917.366 | 173.543 | 116.934 |
| `packet_classifier` | 4.366 | 112.381 | 1295.277 | 87.528 | 907.460 | 166.441 | 119.473 |
| `ring_write` | 5.016 | 106.502 | 1291.462 | 91.335 | 923.574 | 173.181 | 121.050 |
| `histogram_bins` | 4.136 | 115.111 | 1318.797 | 89.895 | 917.800 | 169.701 | 105.939 |
| `prefix_scan` | 5.579 | 115.162 | 1292.038 | 90.824 | 919.322 | 168.533 | 125.381 |
| `binary_search` | 4.784 | 115.390 | 1289.331 | 89.279 | 909.950 | 178.696 | 120.160 |
| `sort_window` | 4.690 | 122.931 | 1291.522 | 97.542 | 921.345 | 181.775 | 117.984 |
| `bloom_filter` | 5.116 | 117.666 | 1293.375 | 97.165 | 916.989 | 174.238 | 125.025 |
| `hash_join` | 12.578 | 249.323 | 1298.418 | 139.141 | 957.639 | 234.164 | 168.739 |
| `sieve` | 3.681 | 116.887 | 1285.854 | 97.052 | 909.100 | 179.587 | 126.768 |
| `fib` | 3.839 | 110.943 | 1281.385 | 84.897 | 913.271 | 161.649 | 108.990 |
| `collatz` | 4.229 | 106.084 | 1297.972 | 86.465 | 913.560 | 164.385 | 112.662 |
| `matmul` | 5.996 | 123.481 | 1285.564 | 101.195 | 930.426 | 203.091 | 150.389 |
| `json_parse` | 82.885 | 835.570 | 1476.667 | 146.218 | 1060.071 | 324.656 | 229.430 |

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
