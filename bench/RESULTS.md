# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-10T20:17:25Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `96504a3bb07b504c3143c48396de8a92ac30e6e1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31427899851 |
| NURL | `v0.36.0-72-g96504a3b` |
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
| _(floor: empty program)_ | _1.865_ | _1.910_ | _2.071_ | _25.354_ | _19.227_ |
| `lcg` | **44.492** | 44.585 | 44.791 | 1838.354 | 5388.582 |
| `packet_classifier` | **63.873** | 63.947 | 64.028 | 158.945 | 4660.041 |
| `ring_write` | **47.895** | 47.920 | 48.160 | 74.463 | 6475.887 |
| `histogram_bins` | **44.836** | 44.925 | 45.059 | 75.883 | 6220.385 |
| `prefix_scan` | **24.704** | 24.807 | 24.968 | 71.483 | 4798.287 |
| `binary_search` | **35.877** | 35.956 | 46.265 | 111.928 | 6433.279 |
| `sort_window` | 30.967 | 30.994 | **30.382** | 165.275 | 11915.988 |
| `bloom_filter` | **19.958** | 20.590 | 20.895 | 2750.728 | 7744.226 |
| `hash_join` | **29.369** | 30.883 | 31.217 | 3407.074 | 8218.856 |
| `sieve` | 20.600 | **20.425** | 20.707 | 71.150 | 3343.847 |
| `fib` | **28.162** | 33.521 | 29.618 | 143.039 | 1287.828 |
| `collatz` | **14.069** | **14.069** | 14.095 | 54.461 | 751.231 |
| `matmul` | **45.267** | 46.315 | 45.801 | 85.142 | 3413.432 |
| `json_parse` | 46.041 | **9.201** | 12.537 | 39.746 | 38.674 |
| `nbody` | 46.534 | 46.566 | **44.434** | 96.430 | 3225.657 |

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
| _(floor: empty program)_ | _3.163_ | _98.338_ | _**101.501**_ | _70.606_ | _67.967_ |
| `lcg` | 3.229 | 100.902 | **104.131** | 78.045 | 77.369 |
| `packet_classifier` | 3.267 | 102.651 | **105.918** | 79.664 | 77.931 |
| `ring_write` | 3.341 | 101.773 | **105.114** | 78.782 | 77.484 |
| `histogram_bins` | 3.427 | 102.589 | **106.016** | 80.061 | 78.563 |
| `prefix_scan` | 3.461 | 103.621 | **107.082** | 81.232 | 79.090 |
| `binary_search` | 3.602 | 102.049 | **105.651** | 77.842 | 82.058 |
| `sort_window` | 3.668 | 113.637 | **117.305** | 85.048 | 84.862 |
| `bloom_filter` | 3.894 | 110.517 | **114.411** | 86.495 | 83.109 |
| `hash_join` | 5.973 | 213.473 | **219.446** | 124.864 | 117.413 |
| `sieve` | 3.445 | 104.893 | **108.338** | 86.046 | 87.559 |
| `fib` | 3.166 | 96.944 | **100.110** | 73.900 | 73.905 |
| `collatz` | 3.416 | 100.125 | **103.541** | 77.233 | 77.120 |
| `matmul` | 3.657 | 108.809 | **112.466** | 89.395 | 99.695 |
| `json_parse` | 42.551 | 528.657 | **571.208** | 130.782 | 190.597 |
| `nbody` | 4.782 | 118.751 | **123.533** | 104.515 | 104.159 |

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
