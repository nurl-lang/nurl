# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T06:57:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `70160f378267f21bfc82f8fdd9810f57a7c12fe8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31466758683 |
| NURL | `v0.37.0-3-g70160f37` |
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
| _(floor: empty program)_ | _1.655_ | _1.730_ | _1.844_ | _21.841_ | _17.046_ |
| `lcg` | **39.254** | 39.283 | 39.391 | 1872.045 | 5163.737 |
| `packet_classifier` | 56.532 | **56.443** | 56.454 | 160.728 | 4501.520 |
| `ring_write` | **42.386** | 42.435 | 42.519 | 66.533 | 6248.432 |
| `histogram_bins` | **39.661** | 41.419 | 39.856 | 66.534 | 6642.813 |
| `prefix_scan` | **21.847** | 21.941 | 22.086 | 64.681 | 4732.486 |
| `binary_search` | 40.211 | **38.809** | 43.317 | 107.742 | 6137.479 |
| `sort_window` | 27.365 | 27.423 | **26.967** | 198.161 | 11444.642 |
| `bloom_filter` | **18.164** | 18.355 | 18.618 | 2830.074 | 7534.631 |
| `hash_join` | **28.076** | 30.076 | 29.954 | 3406.715 | 8239.933 |
| `sieve` | 20.150 | **19.926** | 20.140 | 68.214 | 3302.373 |
| `fib` | **25.256** | 30.083 | 28.262 | 131.814 | 1358.786 |
| `collatz` | 12.618 | **12.501** | 12.586 | 50.824 | 708.644 |
| `matmul` | 33.525 | **33.523** | 33.779 | 76.332 | 3229.807 |
| `json_parse` | 8.949 | **8.840** | 11.766 | 34.422 | 37.075 |
| `nbody` | 40.890 | 40.960 | **39.007** | 102.864 | 3093.619 |

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
| _(floor: empty program)_ | _2.701_ | _79.677_ | _**82.378**_ | _56.001_ | _60.861_ |
| `lcg` | 2.789 | 83.034 | **85.823** | 65.535 | 67.632 |
| `packet_classifier` | 3.013 | 89.298 | **92.311** | 69.230 | 69.821 |
| `ring_write` | 3.124 | 89.399 | **92.523** | 72.217 | 71.972 |
| `histogram_bins` | 3.002 | 93.254 | **96.256** | 72.026 | 74.489 |
| `prefix_scan` | 3.323 | 100.080 | **103.403** | 76.664 | 75.541 |
| `binary_search` | 3.155 | 90.144 | **93.299** | 68.847 | 75.160 |
| `sort_window` | 3.278 | 97.484 | **100.762** | 75.313 | 79.686 |
| `bloom_filter` | 3.457 | 99.365 | **102.822** | 78.652 | 77.001 |
| `hash_join` | 5.579 | 210.444 | **216.023** | 120.453 | 112.426 |
| `sieve` | 3.067 | 91.226 | **94.293** | 77.310 | 79.198 |
| `fib` | 2.850 | 84.660 | **87.510** | 67.314 | 69.283 |
| `collatz` | 2.977 | 91.801 | **94.778** | 71.939 | 71.756 |
| `matmul` | 3.304 | 94.986 | **98.290** | 80.112 | 92.947 |
| `json_parse` | 42.956 | 541.187 | **584.143** | 123.250 | 179.269 |
| `nbody` | 4.438 | 106.476 | **110.914** | 96.854 | 93.860 |

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
