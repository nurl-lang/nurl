# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T05:43:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `09bdb7ec625bb0f9d6d16dda81172e80b375eeb2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30881331951 |
| NURL | `v0.32.0-26-g09bdb7ec` |
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
| _(floor: empty program)_ | _1.380_ | _1.390_ | _1.533_ | _23.736_ | _16.854_ |
| `lcg` | 37.873 | **37.679** | 37.836 | 1768.856 | 5353.847 |
| `packet_classifier` | **52.865** | 53.056 | 53.081 | 157.044 | 4422.338 |
| `ring_write` | **40.621** | 40.714 | 41.236 | 68.763 | 6411.580 |
| `histogram_bins` | 40.687 | 40.866 | **39.840** | 70.545 | 6083.407 |
| `prefix_scan` | 21.459 | 21.933 | **21.065** | 69.020 | 4549.782 |
| `binary_search` | 34.232 | **30.098** | 39.744 | 108.537 | 6325.676 |
| `sort_window` | 37.656 | 46.106 | **35.969** | 182.419 | 11116.735 |
| `bloom_filter` | 14.375 | 14.485 | **13.973** | 2762.235 | 7929.197 |
| `hash_join` | **26.317** | 28.193 | 28.537 | 3394.270 | 7947.536 |
| `sieve` | 36.296 | **33.899** | 37.008 | 85.291 | 3612.141 |
| `fib` | 25.832 | 26.820 | **25.586** | 121.943 | 1158.420 |
| `collatz` | 13.165 | 12.952 | **12.798** | 56.703 | 682.339 |
| `matmul` | 17.379 | **17.311** | 17.574 | 73.309 | 3115.115 |
| `json_parse` | **7.257** | 7.737 | 9.772 | 34.305 | 36.233 |
| `nbody` | 36.185 | 36.208 | **33.551** | 92.803 | 2394.158 |

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
| _(floor: empty program)_ | _2.219_ | _73.932_ | _**76.151**_ | _54.463_ | _56.986_ |
| `lcg` | 2.404 | 79.708 | **82.112** | 61.301 | 64.620 |
| `packet_classifier` | 2.372 | 78.210 | **80.582** | 62.996 | 64.825 |
| `ring_write` | 2.544 | 79.935 | **82.479** | 62.889 | 66.216 |
| `histogram_bins` | 2.801 | 82.609 | **85.410** | 64.106 | 69.039 |
| `prefix_scan` | 2.594 | 84.674 | **87.268** | 66.183 | 67.479 |
| `binary_search` | 2.726 | 82.582 | **85.308** | 64.108 | 71.650 |
| `sort_window` | 2.713 | 90.345 | **93.058** | 69.239 | 74.359 |
| `bloom_filter` | 2.928 | 88.918 | **91.846** | 69.667 | 71.715 |
| `hash_join` | 4.852 | 190.582 | **195.434** | 107.596 | 105.651 |
| `sieve` | 2.730 | 84.156 | **86.886** | 71.369 | 75.962 |
| `fib` | 2.378 | 78.260 | **80.638** | 61.952 | 63.750 |
| `collatz` | 2.600 | 81.280 | **83.880** | 63.461 | 66.476 |
| `matmul` | 2.764 | 87.812 | **90.576** | 73.591 | 87.739 |
| `json_parse` | 37.698 | 461.652 | **499.350** | 111.512 | 177.742 |
| `nbody` | 3.674 | 99.128 | **102.802** | 87.584 | 92.193 |

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
