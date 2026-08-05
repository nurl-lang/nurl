# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T04:58:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0329e85ff58a8fc04a96fa5ccb89f53ae5c8f1ec` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30976467943 |
| NURL | `v0.32.0-63-g0329e85f` |
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
| _(floor: empty program)_ | _1.671_ | _1.729_ | _1.844_ | _22.634_ | _17.137_ |
| `lcg` | **39.227** | 39.325 | 39.356 | 1893.156 | 5108.487 |
| `packet_classifier` | **56.353** | 56.500 | 56.617 | 161.539 | 4610.074 |
| `ring_write` | **42.338** | 42.383 | 42.510 | 65.822 | 6139.372 |
| `histogram_bins` | **39.598** | 41.365 | 39.868 | 66.424 | 6076.356 |
| `prefix_scan` | **21.826** | 21.946 | 21.993 | 64.366 | 4499.831 |
| `binary_search` | 39.885 | **38.280** | 43.151 | 105.721 | 6102.381 |
| `sort_window` | 27.393 | 27.547 | **27.019** | 196.689 | 11773.286 |
| `bloom_filter` | **18.054** | 18.219 | 18.518 | 2861.994 | 7644.058 |
| `hash_join` | **28.086** | 30.199 | 29.983 | 3414.242 | 8150.341 |
| `sieve` | 20.222 | **19.851** | 20.101 | 65.936 | 3478.930 |
| `fib` | **25.202** | 30.039 | 28.279 | 131.633 | 1358.087 |
| `collatz` | **12.437** | 12.494 | 12.596 | 49.384 | 713.309 |
| `matmul` | 33.595 | **33.576** | 33.718 | 74.855 | 3182.561 |
| `json_parse` | **8.743** | 8.866 | 11.730 | 36.166 | 36.914 |
| `nbody` | 40.744 | 40.974 | **39.121** | 98.707 | 2997.311 |

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
| _(floor: empty program)_ | _2.603_ | _78.437_ | _**81.040**_ | _56.802_ | _59.752_ |
| `lcg` | 2.687 | 83.289 | **85.976** | 63.834 | 69.078 |
| `packet_classifier` | 2.795 | 85.303 | **88.098** | 66.553 | 66.547 |
| `ring_write` | 2.887 | 85.972 | **88.859** | 66.260 | 68.227 |
| `histogram_bins` | 2.978 | 89.235 | **92.213** | 69.159 | 73.443 |
| `prefix_scan` | 2.952 | 91.909 | **94.861** | 70.263 | 71.497 |
| `binary_search` | 3.074 | 89.620 | **92.694** | 67.151 | 72.712 |
| `sort_window` | 3.109 | 95.923 | **99.032** | 73.851 | 85.106 |
| `bloom_filter` | 3.289 | 93.906 | **97.195** | 74.176 | 79.639 |
| `hash_join` | 5.256 | 208.345 | **213.601** | 116.935 | 108.650 |
| `sieve` | 2.953 | 90.670 | **93.623** | 76.520 | 77.407 |
| `fib` | 2.729 | 83.261 | **85.990** | 64.458 | 65.831 |
| `collatz` | 2.941 | 88.267 | **91.208** | 65.673 | 69.025 |
| `matmul` | 3.251 | 95.851 | **99.102** | 78.109 | 90.357 |
| `json_parse` | 38.824 | 505.992 | **544.816** | 119.504 | 174.349 |
| `nbody` | 4.202 | 104.987 | **109.189** | 94.166 | 90.902 |

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
