# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T08:37:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `8d4e8b35a285a4c0ff2483d4f153ca6a1089f48c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30892420242 |
| NURL | `v0.32.0-33-g8d4e8b35` |
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
| _(floor: empty program)_ | _1.872_ | _1.871_ | _2.028_ | _23.786_ | _18.318_ |
| `lcg` | **44.334** | 44.361 | 44.454 | 1830.932 | 5292.521 |
| `packet_classifier` | **63.767** | 63.802 | 63.934 | 159.645 | 4496.524 |
| `ring_write` | **47.818** | 47.953 | 48.070 | 73.314 | 6605.033 |
| `histogram_bins` | **44.839** | 44.909 | 45.042 | 74.974 | 7236.641 |
| `prefix_scan` | **24.578** | 24.696 | 24.873 | 71.665 | 4804.105 |
| `binary_search` | **35.612** | 36.085 | 46.219 | 112.343 | 6283.926 |
| `sort_window` | 30.951 | 31.040 | **30.487** | 165.881 | 10920.802 |
| `bloom_filter` | **19.904** | 20.556 | 20.844 | 2770.508 | 7628.302 |
| `hash_join` | **29.382** | 31.048 | 31.264 | 3412.641 | 8152.305 |
| `sieve` | 21.338 | **20.836** | 21.004 | 74.812 | 3457.813 |
| `fib` | **28.139** | 33.481 | 29.469 | 143.667 | 1293.485 |
| `collatz` | 13.950 | **13.943** | 14.093 | 53.475 | 755.167 |
| `matmul` | **45.130** | 45.885 | 46.598 | 84.441 | 3580.104 |
| `json_parse` | **8.816** | 9.229 | 12.507 | 39.173 | 38.419 |
| `nbody` | 46.506 | 46.479 | **44.273** | 95.685 | 3197.766 |

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
| _(floor: empty program)_ | _2.985_ | _95.447_ | _**98.432**_ | _69.439_ | _66.304_ |
| `lcg` | 3.037 | 98.806 | **101.843** | 76.375 | 76.334 |
| `packet_classifier` | 3.137 | 99.300 | **102.437** | 76.591 | 75.983 |
| `ring_write` | 3.202 | 97.437 | **100.639** | 75.191 | 77.626 |
| `histogram_bins` | 3.330 | 105.628 | **108.958** | 78.926 | 78.224 |
| `prefix_scan` | 3.296 | 103.525 | **106.821** | 80.550 | 79.361 |
| `binary_search` | 3.461 | 102.226 | **105.687** | 77.582 | 83.774 |
| `sort_window` | 3.524 | 108.000 | **111.524** | 82.548 | 85.710 |
| `bloom_filter` | 3.680 | 107.079 | **110.759** | 84.954 | 88.911 |
| `hash_join` | 5.771 | 216.612 | **222.383** | 125.806 | 119.624 |
| `sieve` | 3.353 | 107.132 | **110.485** | 87.595 | 88.004 |
| `fib` | 3.089 | 95.995 | **99.084** | 73.892 | 73.414 |
| `collatz` | 3.229 | 100.048 | **103.277** | 77.866 | 77.248 |
| `matmul` | 3.533 | 106.552 | **110.085** | 87.762 | 98.827 |
| `json_parse` | 39.545 | 504.489 | **544.034** | 128.942 | 190.748 |
| `nbody` | 4.640 | 120.593 | **125.233** | 103.567 | 100.558 |

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
