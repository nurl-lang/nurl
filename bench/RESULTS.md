# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T16:59:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377692 KiB |
| Commit | `e8ee1e07bb211700f36ded6815bc82ef614ad520` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30709175486 |
| NURL | `v0.30.0-25-ge8ee1e0` |
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
| _(floor: empty program)_ | _1.647_ | _1.724_ | _1.839_ | _23.827_ | _17.179_ |
| `lcg` | 39.376 | **39.290** | 39.475 | 1880.515 | 5160.013 |
| `packet_classifier` | **56.464** | 56.574 | 56.743 | 161.548 | 4544.666 |
| `ring_write` | 42.448 | **42.342** | 42.494 | 65.685 | 6567.283 |
| `histogram_bins` | **39.628** | 41.407 | 39.802 | 65.756 | 6332.371 |
| `prefix_scan` | 21.986 | **21.935** | 22.088 | 67.657 | 4671.634 |
| `binary_search` | 40.174 | **38.575** | 43.508 | 106.926 | 6018.608 |
| `sort_window` | 27.694 | 27.657 | **27.180** | 196.549 | 11716.550 |
| `bloom_filter` | **18.195** | 18.372 | 18.594 | 2877.102 | 7725.884 |
| `hash_join` | **28.131** | 30.080 | 29.919 | 3437.088 | 8187.202 |
| `sieve` | 20.435 | **19.840** | 19.898 | 66.476 | 3340.999 |
| `fib` | **25.196** | 30.051 | 28.217 | 131.098 | 1354.129 |
| `collatz` | 12.455 | **12.433** | 12.556 | 49.604 | 707.428 |
| `matmul` | **33.588** | 33.615 | 33.603 | 76.239 | 3239.976 |
| `json_parse` | **8.546** | 8.912 | 11.830 | 36.017 | 37.718 |
| `nbody` | 40.862 | 40.866 | **39.070** | 100.448 | 3104.163 |

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
| _(floor: empty program)_ | _2.634_ | _80.618_ | _**83.252**_ | _58.139_ | _60.193_ |
| `lcg` | 2.759 | 86.459 | **89.218** | 66.620 | 68.074 |
| `packet_classifier` | 2.787 | 86.102 | **88.889** | 68.918 | 68.816 |
| `ring_write` | 2.873 | 86.293 | **89.166** | 67.296 | 68.598 |
| `histogram_bins` | 2.923 | 90.318 | **93.241** | 71.651 | 71.826 |
| `prefix_scan` | 2.941 | 90.657 | **93.598** | 72.405 | 71.209 |
| `binary_search` | 3.070 | 91.053 | **94.123** | 71.261 | 73.862 |
| `sort_window` | 3.135 | 96.172 | **99.307** | 74.319 | 79.191 |
| `bloom_filter` | 3.302 | 95.178 | **98.480** | 75.792 | 75.146 |
| `hash_join` | 5.333 | 210.046 | **215.379** | 122.047 | 112.420 |
| `sieve` | 2.980 | 91.255 | **94.235** | 78.606 | 78.831 |
| `fib` | 2.723 | 81.922 | **84.645** | 65.621 | 66.029 |
| `collatz` | 2.828 | 87.238 | **90.066** | 67.957 | 69.633 |
| `matmul` | 3.188 | 94.476 | **97.664** | 79.013 | 90.782 |
| `json_parse` | 39.837 | 512.209 | **552.046** | 121.086 | 179.304 |
| `nbody` | 4.257 | 105.779 | **110.036** | 95.228 | 92.109 |

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
