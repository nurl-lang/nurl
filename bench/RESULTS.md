# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T07:32:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `32e2e621a5ea6fdb7bc9871db914bc96b25dc364` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31246208631 |
| NURL | `v0.35.1-27-g32e2e621` |
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
| _(floor: empty program)_ | _1.772_ | _1.890_ | _1.987_ | _24.734_ | _18.110_ |
| `lcg` | **44.310** | 44.358 | 44.516 | 1831.892 | 5320.833 |
| `packet_classifier` | 63.792 | **63.749** | 63.891 | 159.059 | 5223.422 |
| `ring_write` | **47.819** | 47.940 | 48.058 | 74.015 | 6725.155 |
| `histogram_bins` | **44.822** | 44.910 | 44.997 | 75.368 | 6269.784 |
| `prefix_scan` | **24.638** | 24.709 | 24.930 | 72.528 | 4651.004 |
| `binary_search` | **35.545** | 35.883 | 46.179 | 110.431 | 6395.843 |
| `sort_window` | 30.825 | 30.951 | **30.351** | 164.971 | 11855.703 |
| `bloom_filter` | **19.951** | 20.516 | 20.872 | 2815.717 | 7845.844 |
| `hash_join` | **29.321** | 30.909 | 31.213 | 3473.198 | 8189.725 |
| `sieve` | 20.680 | 20.348 | **20.321** | 70.575 | 3629.376 |
| `fib` | **28.143** | 33.477 | 29.579 | 142.996 | 1290.723 |
| `collatz` | 13.939 | **13.919** | 14.116 | 51.814 | 755.897 |
| `matmul` | 46.561 | 46.481 | **46.256** | 84.464 | 3489.995 |
| `json_parse` | 46.006 | **9.180** | 12.448 | 38.072 | 38.517 |
| `nbody` | 46.261 | 46.462 | **44.235** | 96.768 | 3348.782 |

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
| _(floor: empty program)_ | _3.032_ | _89.842_ | _**92.874**_ | _64.031_ | _67.285_ |
| `lcg` | 3.131 | 94.356 | **97.487** | 73.495 | 74.606 |
| `packet_classifier` | 3.196 | 95.841 | **99.037** | 74.014 | 73.886 |
| `ring_write` | 3.251 | 97.564 | **100.815** | 75.672 | 75.440 |
| `histogram_bins` | 3.374 | 100.037 | **103.411** | 76.953 | 78.752 |
| `prefix_scan` | 3.428 | 101.125 | **104.553** | 80.157 | 78.398 |
| `binary_search` | 3.510 | 101.814 | **105.324** | 77.754 | 81.430 |
| `sort_window` | 3.610 | 107.068 | **110.678** | 81.954 | 84.461 |
| `bloom_filter` | 3.720 | 104.843 | **108.563** | 81.901 | 82.543 |
| `hash_join` | 5.748 | 210.726 | **216.474** | 121.699 | 116.144 |
| `sieve` | 3.391 | 100.893 | **104.284** | 83.914 | 85.653 |
| `fib` | 3.134 | 94.431 | **97.565** | 73.562 | 74.920 |
| `collatz` | 3.446 | 99.053 | **102.499** | 74.936 | 77.762 |
| `matmul` | 3.635 | 105.593 | **109.228** | 86.151 | 99.108 |
| `json_parse` | 40.717 | 521.575 | **562.292** | 127.197 | 188.043 |
| `nbody` | 4.666 | 116.314 | **120.980** | 101.935 | 99.186 |

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
