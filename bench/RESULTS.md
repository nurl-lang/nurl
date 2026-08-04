# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T21:07:54Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `eb74ee574afbe368a6321a4e5fe74177addce729` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30950661333 |
| NURL | `v0.32.0-56-geb74ee57` |
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
| _(floor: empty program)_ | _1.675_ | _1.758_ | _1.904_ | _22.789_ | _17.700_ |
| `lcg` | 39.417 | **39.404** | 39.576 | 1890.398 | 5087.019 |
| `packet_classifier` | 56.479 | **56.444** | 56.615 | 162.030 | 4510.563 |
| `ring_write` | **42.374** | 42.610 | 42.813 | 67.181 | 6347.696 |
| `histogram_bins` | **39.883** | 41.634 | 40.212 | 67.783 | 6070.013 |
| `prefix_scan` | **22.065** | 22.069 | 22.352 | 66.398 | 4637.075 |
| `binary_search` | 40.199 | **38.701** | 43.668 | 107.694 | 6042.510 |
| `sort_window` | 27.701 | 27.731 | **27.129** | 199.953 | 11690.038 |
| `bloom_filter` | **18.207** | 18.488 | 18.733 | 2885.704 | 7823.989 |
| `hash_join` | **28.127** | 30.148 | 30.158 | 3444.648 | 8226.914 |
| `sieve` | 20.556 | **20.048** | 20.246 | 67.979 | 3324.459 |
| `fib` | **25.240** | 30.054 | 28.379 | 132.922 | 1361.714 |
| `collatz` | **12.589** | 12.665 | 12.727 | 50.265 | 718.683 |
| `matmul` | 33.942 | **33.781** | 33.943 | 77.927 | 3136.131 |
| `json_parse` | **8.785** | 8.935 | 11.869 | 36.918 | 38.244 |
| `nbody` | 40.903 | 40.968 | **39.346** | 102.113 | 3038.336 |

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
| _(floor: empty program)_ | _2.765_ | _83.274_ | _**86.039**_ | _59.752_ | _63.047_ |
| `lcg` | 2.731 | 87.532 | **90.263** | 67.997 | 70.470 |
| `packet_classifier` | 2.830 | 86.836 | **89.666** | 67.890 | 68.417 |
| `ring_write` | 2.887 | 87.636 | **90.523** | 68.652 | 70.344 |
| `histogram_bins` | 3.010 | 99.147 | **102.157** | 73.461 | 75.998 |
| `prefix_scan` | 3.078 | 98.470 | **101.548** | 76.387 | 75.093 |
| `binary_search` | 3.106 | 97.283 | **100.389** | 72.401 | 78.115 |
| `sort_window` | 3.248 | 105.341 | **108.589** | 79.445 | 80.046 |
| `bloom_filter` | 3.422 | 99.934 | **103.356** | 78.965 | 76.843 |
| `hash_join` | 5.367 | 214.460 | **219.827** | 122.012 | 112.610 |
| `sieve` | 2.995 | 92.657 | **95.652** | 78.789 | 79.684 |
| `fib` | 2.802 | 86.515 | **89.317** | 66.826 | 67.176 |
| `collatz` | 2.940 | 94.784 | **97.724** | 70.684 | 71.891 |
| `matmul` | 3.237 | 102.740 | **105.977** | 84.100 | 95.888 |
| `json_parse` | 39.843 | 526.564 | **566.407** | 127.741 | 181.523 |
| `nbody` | 4.389 | 110.292 | **114.681** | 99.466 | 94.122 |

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
