# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-29T09:05:34Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `35895d02ff6be871a71d17a816c49a5c3973760e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30437804015 |
| NURL | `v0.27.0-52-g35895d0` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.1 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `clang -O2`, Rust `-C opt-level=2` |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.654_ | _1.695_ | _1.832_ | _22.218_ | _16.819_ |
| `lcg` | **39.146** | 39.231 | 39.397 | 1873.625 | 5216.726 |
| `packet_classifier` | **56.206** | 56.465 | 56.599 | 161.264 | 4524.887 |
| `ring_write` | **42.321** | 42.350 | 42.525 | 66.191 | 6381.796 |
| `histogram_bins` | **39.646** | 41.438 | 39.806 | 66.297 | 6321.233 |
| `prefix_scan` | **21.861** | 21.862 | 21.995 | 64.840 | 4788.306 |
| `binary_search` | 39.867 | **38.414** | 43.344 | 105.754 | 5866.802 |
| `sort_window` | 27.381 | 27.494 | **26.919** | 196.885 | 12068.710 |
| `bloom_filter` | **17.993** | 18.269 | 18.491 | 2820.719 | 7648.291 |
| `hash_join` | **27.978** | 30.180 | 29.988 | 3414.935 | 8294.170 |
| `sieve` | 18.463 | **17.876** | 18.157 | 65.548 | 3286.151 |
| `fib` | **25.319** | 29.969 | 28.394 | 131.486 | 1348.033 |
| `collatz` | **12.493** | 12.591 | 12.541 | 49.091 | 714.951 |
| `matmul` | **33.469** | 33.539 | 33.697 | 74.190 | 3286.289 |
| `json_parse` | **8.479** | 8.962 | 11.801 | 35.682 | 37.161 |
| `nbody` | 40.892 | 40.869 | **38.993** | 100.859 | 3024.385 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns. The floor row is what each
toolchain costs for a program that does nothing — for NURL that is
dominated by the LTO link every NURL binary pays for, so subtract it to
read the marginal cost of the benchmark itself. Node and Python have no
column here: they compile at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.938_ | _76.735_ | _**79.673**_ | _54.981_ | _64.935_ |
| `lcg` | 3.074 | 82.055 | **85.129** | 65.109 | 66.064 |
| `packet_classifier` | 3.167 | 82.712 | **85.879** | 66.067 | 67.563 |
| `ring_write` | 3.282 | 84.532 | **87.814** | 67.470 | 68.006 |
| `histogram_bins` | 3.392 | 88.780 | **92.172** | 68.801 | 72.455 |
| `prefix_scan` | 3.508 | 88.737 | **92.245** | 70.081 | 69.838 |
| `binary_search` | 3.805 | 88.701 | **92.506** | 67.228 | 72.848 |
| `sort_window` | 3.872 | 93.911 | **97.783** | 73.674 | 78.312 |
| `bloom_filter` | 4.081 | 94.197 | **98.278** | 74.255 | 79.092 |
| `hash_join` | 8.709 | 206.202 | **214.911** | 116.617 | 107.708 |
| `sieve` | 3.492 | 91.108 | **94.600** | 78.013 | 76.877 |
| `fib` | 3.018 | 82.345 | **85.363** | 65.947 | 67.128 |
| `collatz` | 3.371 | 89.951 | **93.322** | 65.404 | 68.853 |
| `matmul` | 4.412 | 93.337 | **97.749** | 77.949 | 89.658 |
| `json_parse` | 72.110 | 710.044 | **782.154** | 121.521 | 176.959 |
| `nbody` | 7.120 | 103.496 | **110.616** | 94.178 | 90.571 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
line. A speed number for a program computing something else is worthless,
so a mismatch drops the row out of the tables above rather than being
reported as a fast cell.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical across 5 languages |
| `packet_classifier` | `4205972061` | identical across 5 languages |
| `ring_write` | `8299504528805184357` | identical across 5 languages |
| `histogram_bins` | `1215643728` | identical across 5 languages |
| `prefix_scan` | `492982549` | identical across 5 languages |
| `binary_search` | `805907445` | identical across 5 languages |
| `sort_window` | `2815490238` | identical across 5 languages |
| `bloom_filter` | `2351703` | identical across 5 languages |
| `hash_join` | `6152419568754618368` | identical across 5 languages |
| `sieve` | `664579` | identical across 5 languages |
| `fib` | `9227465` | identical across 5 languages |
| `collatz` | `350` | identical across 5 languages |
| `matmul` | `393199` | identical across 5 languages |
| `json_parse` | `20` | identical across 5 languages |
| `nbody` | `4595260366167553674` | identical across 5 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Nine of the fifteen benchmarks are defined over 64-bit unsigned integers.
  Python has arbitrary-precision integers and masks; JS has no 64-bit
  integer at all, so those rows use `BigInt` where the algorithm genuinely
  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each
  file says which and why. That gap *is* part of what this table reports.
* `nbody` is the counterweight to the row above, and the only row defined
  over IEEE-754 doubles rather than integers. That is the type JavaScript
  does have — its one numeric type is the double — so Node runs the same
  arithmetic as the compiled backends with no representation tax, and lands
  near 2x C instead of the 30-50x the BigInt rows cost it. It is also the
  only row whose critical path runs through the FPU's long-latency sqrt and
  divide units rather than the integer ALU. All five ports use the same
  operation order and the same struct-of-arrays layout, so the checksum —
  the final energy's bit pattern — is exact across all five.
* `json_parse` is the one row whose gate is "every parser accepted the
  document" rather than a structural checksum: each language uses the
  parser in its own box (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`), and C and Rust — whose boxes are empty — carry a
  small hand-written recursive-descent parser in the benchmark file.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
