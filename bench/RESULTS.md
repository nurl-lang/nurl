# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-26T19:51:54Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `Intel Core i7-5930K @ 3.50 GHz, Ubuntu 24.04` |
| Kernel | `Linux 7.0.0-28-generic x86_64` |
| CPU | Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (12 logical cores) |
| Memory | 32770952 KiB |
| Commit | `9f8058d034a4f136ab682ed81e5e515d32f06d33` |
| NURL | `v0.25.1-8-g91e2d42` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.82.0 (f6e511eec 2024-10-15) |
| Node | v24.15.0 |
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
| _(floor: empty program)_ | _1.871_ | _1.815_ | _2.010_ | _28.078_ | _12.521_ |
| `lcg` | **4.348** | 19.941 | 18.466 | 6422.439 | 19398.585 |
| `affine_mix` | **14.257** | 15.295 | 19.119 | 1531.033 | 5827.961 |
| `packet_classifier` | 69.635 | 68.250 | **61.123** | 145.181 | 5268.486 |
| `ring_write` | **33.791** | 35.109 | 34.848 | 69.386 | 5574.670 |
| `histogram_bins` | 30.508 | 30.071 | **26.716** | 68.676 | 5431.674 |
| `prefix_scan` | **24.413** | 24.981 | 25.070 | 78.461 | 5914.341 |
| `binary_search` | **35.184** | 37.143 | 46.694 | 179.365 | 8195.616 |
| `sort_window` | **48.663** | 71.542 | 53.964 | 188.228 | 13574.864 |
| `bloom_filter` | 18.337 | **13.920** | 16.439 | 3150.609 | 8814.954 |
| `hash_join` | **6.038** | 6.283 | 7.026 | 429.218 | 917.646 |
| `sieve` | 43.893 | 42.001 | **37.929** | 98.866 | 4035.681 |
| `fib` | 34.355 | 33.811 | **33.580** | 171.502 | 1361.877 |
| `collatz` | 18.773 | **17.658** | 19.043 | 62.582 | 806.903 |
| `matmul` | **33.948** | 34.767 | 36.164 | 120.891 | 4237.984 |
| `json_parse` | 15.011 | **3.821** | 15.703 | 48.870 | 46.059 |

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
| _(floor: empty program)_ | _2.835_ | _98.651_ | _**101.486**_ | _77.908_ | _161.751_ |
| `lcg` | 3.753 | 104.918 | **108.671** | 87.658 | 178.714 |
| `affine_mix` | 3.843 | 117.752 | **121.595** | 91.420 | 176.722 |
| `packet_classifier` | 3.652 | 104.073 | **107.725** | 90.662 | 169.880 |
| `ring_write` | 4.307 | 108.722 | **113.029** | 90.483 | 181.313 |
| `histogram_bins` | 5.070 | 112.239 | **117.309** | 93.869 | 170.499 |
| `prefix_scan` | 4.548 | 115.278 | **119.826** | 95.182 | 177.596 |
| `binary_search` | 4.730 | 112.643 | **117.373** | 93.867 | 180.128 |
| `sort_window` | 4.755 | 120.218 | **124.973** | 102.084 | 186.592 |
| `bloom_filter` | 5.278 | 119.390 | **124.668** | 97.554 | 184.148 |
| `hash_join` | 11.679 | 242.682 | **254.361** | 142.832 | 231.801 |
| `sieve` | 3.580 | 112.889 | **116.469** | 99.901 | 185.389 |
| `fib` | 3.764 | 104.819 | **108.583** | 88.789 | 175.940 |
| `collatz` | 4.201 | 111.546 | **115.747** | 88.575 | 179.354 |
| `matmul` | 5.516 | 119.288 | **124.804** | 105.911 | 211.332 |
| `json_parse` | 81.216 | 773.345 | **854.561** | 130.580 | 323.451 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
line. A speed number for a program computing something else is worthless,
so a mismatch drops the row out of the tables above rather than being
reported as a fast cell.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `6299863613973285121` | identical across 5 languages |
| `affine_mix` | `23394348946257561` | identical across 5 languages |
| `packet_classifier` | `4205972061` | identical across 5 languages |
| `ring_write` | `3856155665848586533` | identical across 5 languages |
| `histogram_bins` | `3775845141` | identical across 5 languages |
| `prefix_scan` | `492982549` | identical across 5 languages |
| `binary_search` | `805907445` | identical across 5 languages |
| `sort_window` | `2815490238` | identical across 5 languages |
| `bloom_filter` | `2351703` | identical across 5 languages |
| `hash_join` | `2814341850483607168` | identical across 5 languages |
| `sieve` | `664579` | identical across 5 languages |
| `fib` | `9227465` | identical across 5 languages |
| `collatz` | `350` | identical across 5 languages |
| `matmul` | `393199` | identical across 5 languages |
| `json_parse` | `20` | identical across 5 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Ten of the fifteen benchmarks are defined over 64-bit unsigned integers.
  Python has arbitrary-precision integers and masks; JS has no 64-bit
  integer at all, so those rows use `BigInt` where the algorithm genuinely
  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each
  file says which and why. That gap *is* part of what this table reports.
* `json_parse` is the one row whose gate is "every parser accepted the
  document" rather than a structural checksum: each language uses the
  parser in its own box (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`), and C and Rust — whose boxes are empty — carry a
  small hand-written recursive-descent parser in the benchmark file.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
