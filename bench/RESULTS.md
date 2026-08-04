# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T05:16:51Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377740 KiB |
| Commit | `29840521db10248fafc3b5ac4e292cb84ead1797` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30879957602 |
| NURL | `v0.32.0-23-g29840521` |
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
| _(floor: empty program)_ | _1.746_ | _1.753_ | _1.906_ | _23.570_ | _17.807_ |
| `lcg` | 39.520 | **39.485** | 39.616 | 1883.642 | 5082.539 |
| `packet_classifier` | **56.674** | 56.705 | 56.926 | 163.215 | 4496.928 |
| `ring_write` | 42.795 | **42.755** | 42.868 | 67.289 | 6664.430 |
| `histogram_bins` | **39.814** | 41.513 | 40.065 | 67.154 | 5920.958 |
| `prefix_scan` | **21.936** | 22.057 | 22.175 | 66.414 | 4407.837 |
| `binary_search` | 40.380 | **38.635** | 43.582 | 107.621 | 5868.030 |
| `sort_window` | 27.831 | 27.683 | **27.294** | 200.241 | 11278.428 |
| `bloom_filter` | **18.463** | 18.685 | 18.918 | 2853.006 | 7510.369 |
| `hash_join` | **28.260** | 30.390 | 30.179 | 3447.306 | 8114.101 |
| `sieve` | 18.872 | **18.573** | 18.584 | 67.399 | 3229.142 |
| `fib` | **25.530** | 30.520 | 28.690 | 134.253 | 1350.109 |
| `collatz` | **12.537** | 12.560 | 12.818 | 52.125 | 717.951 |
| `matmul` | 34.219 | **33.908** | 34.416 | 78.600 | 3154.194 |
| `json_parse` | **8.903** | 9.198 | 12.231 | 38.899 | 39.929 |
| `nbody` | 41.252 | 41.244 | **39.385** | 102.440 | 3059.680 |

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
| _(floor: empty program)_ | _2.763_ | _83.650_ | _**86.413**_ | _64.427_ | _61.923_ |
| `lcg` | 2.851 | 89.022 | **91.873** | 70.211 | 69.890 |
| `packet_classifier` | 2.889 | 92.042 | **94.931** | 71.071 | 69.238 |
| `ring_write` | 3.005 | 92.737 | **95.742** | 71.712 | 72.025 |
| `histogram_bins` | 3.235 | 93.904 | **97.139** | 73.970 | 74.238 |
| `prefix_scan` | 3.015 | 96.854 | **99.869** | 75.583 | 74.387 |
| `binary_search` | 3.127 | 93.588 | **96.715** | 73.518 | 76.652 |
| `sort_window` | 3.227 | 103.060 | **106.287** | 80.395 | 81.016 |
| `bloom_filter` | 3.472 | 102.134 | **105.606** | 82.446 | 84.410 |
| `hash_join` | 5.578 | 218.187 | **223.765** | 126.480 | 113.860 |
| `sieve` | 3.038 | 96.622 | **99.660** | 82.986 | 80.196 |
| `fib` | 2.915 | 91.167 | **94.082** | 71.943 | 72.230 |
| `collatz` | 3.099 | 94.968 | **98.067** | 72.569 | 72.634 |
| `matmul` | 3.530 | 105.043 | **108.573** | 88.516 | 100.046 |
| `json_parse` | 41.226 | 535.874 | **577.100** | 129.442 | 189.409 |
| `nbody` | 4.579 | 113.266 | **117.845** | 101.921 | 97.042 |

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
