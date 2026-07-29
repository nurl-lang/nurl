# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-29T12:55:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `efff2ae75321afc5d3271d2f11865ae0499de35f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30453280256 |
| NURL | `v0.28.0` |
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
| _(floor: empty program)_ | _1.778_ | _1.868_ | _2.023_ | _26.943_ | _19.346_ |
| `lcg` | **44.249** | 44.370 | 44.567 | 1831.821 | 5358.397 |
| `packet_classifier` | **63.798** | 63.813 | 63.970 | 158.798 | 4536.304 |
| `ring_write` | **47.810** | 47.899 | 48.066 | 73.951 | 6541.379 |
| `histogram_bins` | **44.902** | 44.938 | 45.119 | 75.620 | 6433.137 |
| `prefix_scan` | **24.649** | 24.765 | 24.883 | 71.824 | 4874.350 |
| `binary_search` | **35.790** | 36.156 | 46.124 | 110.084 | 6522.326 |
| `sort_window` | 30.922 | 31.016 | **30.433** | 164.455 | 11208.596 |
| `bloom_filter` | **19.893** | 20.531 | 20.876 | 2770.898 | 8074.535 |
| `hash_join` | **29.268** | 30.906 | 31.366 | 3471.266 | 8221.296 |
| `sieve` | 20.695 | **20.337** | 20.899 | 71.083 | 3546.357 |
| `fib` | **28.134** | 33.449 | 29.577 | 142.762 | 1299.365 |
| `collatz` | **13.947** | 13.959 | 14.038 | 52.945 | 754.072 |
| `matmul` | **45.837** | 47.118 | 46.993 | 84.878 | 3520.274 |
| `json_parse` | **8.374** | 9.085 | 12.578 | 37.730 | 38.765 |
| `nbody` | 46.460 | 46.432 | **44.271** | 96.212 | 3282.605 |

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
| _(floor: empty program)_ | _3.242_ | _90.697_ | _**93.939**_ | _65.351_ | _72.285_ |
| `lcg` | 3.455 | 97.009 | **100.464** | 75.173 | 75.348 |
| `packet_classifier` | 3.591 | 95.585 | **99.176** | 75.829 | 74.763 |
| `ring_write` | 3.772 | 97.974 | **101.746** | 77.749 | 76.275 |
| `histogram_bins` | 3.974 | 102.852 | **106.826** | 79.255 | 78.650 |
| `prefix_scan` | 4.047 | 100.716 | **104.763** | 79.200 | 80.946 |
| `binary_search` | 4.292 | 99.200 | **103.492** | 76.008 | 81.538 |
| `sort_window` | 4.386 | 105.607 | **109.993** | 81.787 | 84.441 |
| `bloom_filter` | 4.553 | 102.670 | **107.223** | 81.756 | 86.452 |
| `hash_join` | 9.626 | 208.681 | **218.307** | 122.470 | 117.102 |
| `sieve` | 4.016 | 98.947 | **102.963** | 84.401 | 85.142 |
| `fib` | 3.450 | 92.279 | **95.729** | 73.097 | 73.588 |
| `collatz` | 3.735 | 96.048 | **99.783** | 74.826 | 77.227 |
| `matmul` | 4.931 | 103.216 | **108.147** | 84.941 | 98.407 |
| `json_parse` | 78.060 | 695.589 | **773.649** | 131.418 | 186.796 |
| `nbody` | 7.951 | 114.163 | **122.114** | 100.535 | 124.599 |

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
