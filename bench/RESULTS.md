# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T20:45:20Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `293c99ef3bc04f3a61e5a406adefaf19ef6e95d4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30717502646 |
| NURL | `v0.30.0-34-g293c99e` |
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
| _(floor: empty program)_ | _1.649_ | _1.727_ | _1.876_ | _22.559_ | _17.109_ |
| `lcg` | **39.168** | 39.364 | 39.485 | 1870.778 | 5162.398 |
| `packet_classifier` | **56.431** | 56.455 | 56.562 | 160.651 | 4456.538 |
| `ring_write` | **42.285** | 42.393 | 42.578 | 64.983 | 6202.395 |
| `histogram_bins` | **39.649** | 41.330 | 39.926 | 65.696 | 6095.598 |
| `prefix_scan` | **21.853** | 21.969 | 22.097 | 64.296 | 4681.741 |
| `binary_search` | 39.752 | **38.499** | 43.370 | 105.758 | 6280.548 |
| `sort_window` | 27.290 | 27.511 | **26.870** | 196.610 | 11164.616 |
| `bloom_filter` | **18.047** | 18.177 | 18.467 | 2827.434 | 7383.123 |
| `hash_join` | **28.011** | 30.152 | 29.894 | 3414.709 | 8290.610 |
| `sieve` | 20.215 | **20.100** | 20.311 | 66.213 | 3445.859 |
| `fib` | **25.358** | 30.071 | 28.278 | 129.496 | 1353.261 |
| `collatz` | 12.470 | **12.461** | 12.576 | 49.041 | 713.994 |
| `matmul` | **33.561** | 33.617 | 33.748 | 75.447 | 3188.637 |
| `json_parse` | **8.613** | 8.894 | 11.847 | 34.439 | 37.297 |
| `nbody` | 40.855 | 40.984 | **39.064** | 99.180 | 3041.776 |

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
| _(floor: empty program)_ | _2.838_ | _77.556_ | _**80.394**_ | _57.059_ | _60.550_ |
| `lcg` | 2.766 | 82.568 | **85.334** | 65.175 | 68.437 |
| `packet_classifier` | 2.817 | 86.729 | **89.546** | 66.520 | 68.271 |
| `ring_write` | 2.904 | 84.285 | **87.189** | 66.372 | 71.214 |
| `histogram_bins` | 2.951 | 87.461 | **90.412** | 68.805 | 70.584 |
| `prefix_scan` | 2.975 | 89.221 | **92.196** | 71.656 | 71.951 |
| `binary_search` | 3.127 | 88.168 | **91.295** | 68.124 | 72.923 |
| `sort_window` | 3.131 | 94.332 | **97.463** | 74.364 | 78.184 |
| `bloom_filter` | 3.350 | 94.058 | **97.408** | 75.429 | 73.734 |
| `hash_join` | 5.348 | 206.991 | **212.339** | 118.703 | 109.774 |
| `sieve` | 2.980 | 89.115 | **92.095** | 76.729 | 78.891 |
| `fib` | 2.725 | 82.006 | **84.731** | 65.070 | 65.740 |
| `collatz` | 2.888 | 86.797 | **89.685** | 66.754 | 69.109 |
| `matmul` | 3.224 | 93.017 | **96.241** | 79.118 | 91.455 |
| `json_parse` | 40.120 | 507.562 | **547.682** | 120.934 | 177.201 |
| `nbody` | 4.209 | 104.459 | **108.668** | 94.524 | 91.265 |

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
