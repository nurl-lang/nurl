# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T03:50:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `40c0c9edc65781166ef904dc05699c46a55fdeb1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31456381454 |
| NURL | `v0.36.0-93-g40c0c9ed` |
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
| _(floor: empty program)_ | _1.706_ | _1.752_ | _1.862_ | _22.720_ | _17.629_ |
| `lcg` | 39.394 | **39.349** | 39.516 | 1902.253 | 5162.800 |
| `packet_classifier` | **56.615** | 56.761 | 56.911 | 163.197 | 4372.739 |
| `ring_write` | 42.426 | **42.367** | 42.576 | 66.820 | 6412.703 |
| `histogram_bins` | **39.898** | 41.611 | 39.945 | 65.902 | 6057.131 |
| `prefix_scan` | **21.983** | 21.991 | 22.138 | 65.418 | 4470.611 |
| `binary_search` | 39.974 | **38.551** | 43.299 | 107.483 | 5830.052 |
| `sort_window` | 27.444 | 27.534 | **26.975** | 198.658 | 13088.348 |
| `bloom_filter` | **18.041** | 18.321 | 18.653 | 2843.982 | 7555.444 |
| `hash_join` | **28.227** | 30.367 | 30.398 | 3461.325 | 8214.775 |
| `sieve` | 21.040 | **20.475** | 20.902 | 68.467 | 3232.220 |
| `fib` | **25.509** | 30.103 | 28.528 | 132.980 | 1368.704 |
| `collatz` | 12.514 | **12.497** | 12.753 | 50.458 | 722.088 |
| `matmul` | 34.139 | **33.919** | 34.105 | 76.935 | 4691.503 |
| `json_parse` | 42.456 | **8.986** | 11.880 | 36.227 | 38.506 |
| `nbody` | 41.157 | 41.192 | **39.323** | 100.858 | 3085.960 |

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
| _(floor: empty program)_ | _3.111_ | _81.856_ | _**84.967**_ | _58.657_ | _64.864_ |
| `lcg` | 2.851 | 90.234 | **93.085** | 69.386 | 69.971 |
| `packet_classifier` | 2.941 | 89.275 | **92.216** | 69.613 | 70.770 |
| `ring_write` | 2.977 | 89.795 | **92.772** | 69.994 | 74.591 |
| `histogram_bins` | 3.110 | 94.847 | **97.957** | 72.016 | 74.870 |
| `prefix_scan` | 3.124 | 95.404 | **98.528** | 73.846 | 73.043 |
| `binary_search` | 3.218 | 93.451 | **96.669** | 71.044 | 75.282 |
| `sort_window` | 3.223 | 99.911 | **103.134** | 76.354 | 80.960 |
| `bloom_filter` | 3.417 | 97.231 | **100.648** | 76.964 | 76.085 |
| `hash_join` | 5.829 | 217.384 | **223.213** | 122.428 | 113.614 |
| `sieve` | 3.110 | 95.799 | **98.909** | 80.602 | 85.889 |
| `fib` | 2.903 | 89.425 | **92.328** | 69.371 | 68.560 |
| `collatz` | 3.070 | 92.782 | **95.852** | 70.273 | 71.738 |
| `matmul` | 3.374 | 100.756 | **104.130** | 82.724 | 114.450 |
| `json_parse` | 42.180 | 552.004 | **594.184** | 125.157 | 182.810 |
| `nbody` | 4.396 | 109.075 | **113.471** | 96.670 | 94.293 |

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
