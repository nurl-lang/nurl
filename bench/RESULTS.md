# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-06T09:17:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a5214da5810c8cc452144ec80c4565cf78337505` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31088092129 |
| NURL | `v0.33.0-71-ga5214da5` |
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
| _(floor: empty program)_ | _1.649_ | _1.737_ | _1.877_ | _23.478_ | _17.086_ |
| `lcg` | 39.372 | 39.384 | **39.366** | 1872.836 | 5310.962 |
| `packet_classifier` | **56.553** | 56.623 | 56.821 | 162.714 | 4342.335 |
| `ring_write` | 42.583 | **42.496** | 42.577 | 65.967 | 6197.171 |
| `histogram_bins` | **39.601** | 41.304 | 39.829 | 65.159 | 6020.346 |
| `prefix_scan` | 21.876 | **21.853** | 22.038 | 65.001 | 4557.934 |
| `binary_search` | 39.742 | **38.416** | 43.195 | 105.678 | 6070.175 |
| `sort_window` | 27.391 | 27.379 | **26.943** | 196.311 | 14109.071 |
| `bloom_filter` | **18.136** | 18.271 | 18.490 | 2828.546 | 7376.194 |
| `hash_join` | **28.132** | 30.130 | 30.127 | 3412.023 | 8299.584 |
| `sieve` | 20.696 | **20.548** | 20.728 | 65.896 | 3881.607 |
| `fib` | **25.333** | 29.943 | 28.285 | 130.081 | 1349.166 |
| `collatz` | **12.455** | 12.459 | 12.533 | 49.324 | 721.427 |
| `matmul` | 33.796 | **33.658** | 33.823 | 75.111 | 3200.139 |
| `json_parse` | **8.803** | 8.912 | 11.787 | 34.514 | 36.979 |
| `nbody` | 40.825 | 40.994 | **39.061** | 100.585 | 3022.466 |

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
| _(floor: empty program)_ | _2.645_ | _80.733_ | _**83.378**_ | _56.371_ | _66.556_ |
| `lcg` | 2.737 | 83.120 | **85.857** | 64.527 | 69.008 |
| `packet_classifier` | 2.768 | 85.120 | **87.888** | 66.459 | 66.837 |
| `ring_write` | 2.860 | 86.168 | **89.028** | 67.598 | 72.202 |
| `histogram_bins` | 2.939 | 89.451 | **92.390** | 69.020 | 70.705 |
| `prefix_scan` | 3.046 | 92.256 | **95.302** | 71.052 | 72.207 |
| `binary_search` | 3.055 | 89.286 | **92.341** | 68.063 | 76.157 |
| `sort_window` | 3.180 | 96.881 | **100.061** | 73.789 | 79.396 |
| `bloom_filter` | 3.284 | 94.093 | **97.377** | 74.222 | 74.649 |
| `hash_join` | 5.306 | 208.334 | **213.640** | 117.844 | 114.247 |
| `sieve` | 3.000 | 91.184 | **94.184** | 78.744 | 79.038 |
| `fib` | 2.754 | 82.646 | **85.400** | 64.835 | 66.820 |
| `collatz` | 2.948 | 89.189 | **92.137** | 67.402 | 69.565 |
| `matmul` | 3.200 | 95.649 | **98.849** | 78.706 | 90.905 |
| `json_parse` | 40.695 | 520.987 | **561.682** | 122.545 | 179.104 |
| `nbody` | 4.256 | 106.123 | **110.379** | 94.750 | 92.140 |

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
