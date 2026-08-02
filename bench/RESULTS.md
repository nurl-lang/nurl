# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-02T20:28:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `68e05f0c76d43cb0718e0c249a005e10a96af8ec` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30765509066 |
| NURL | `v0.31.0` |
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
| _(floor: empty program)_ | _1.835_ | _1.989_ | _2.081_ | _27.619_ | _19.254_ |
| `lcg` | **44.538** | 44.689 | 44.756 | 1832.707 | 5285.715 |
| `packet_classifier` | 63.933 | **63.872** | 64.039 | 158.014 | 4632.098 |
| `ring_write` | 47.909 | **47.900** | 48.077 | 74.232 | 6710.779 |
| `histogram_bins` | **44.920** | 45.022 | 45.189 | 75.899 | 6811.931 |
| `prefix_scan` | **24.754** | 24.820 | 24.974 | 72.085 | 4738.792 |
| `binary_search` | **35.913** | 36.024 | 46.205 | 115.409 | 6347.400 |
| `sort_window` | 30.970 | 31.111 | **30.434** | 167.107 | 11957.641 |
| `bloom_filter` | **19.918** | 20.620 | 20.980 | 2801.730 | 8041.801 |
| `hash_join` | **29.320** | 30.854 | 31.340 | 3424.919 | 8283.663 |
| `sieve` | 20.982 | 20.665 | **20.615** | 72.167 | 3831.865 |
| `fib` | **28.087** | 33.481 | 29.511 | 146.550 | 1288.549 |
| `collatz` | **13.975** | 14.019 | 14.168 | 52.728 | 752.948 |
| `matmul` | **46.237** | 46.344 | 47.514 | 84.027 | 3531.347 |
| `json_parse` | **8.522** | 9.136 | 12.438 | 39.016 | 39.362 |
| `nbody` | 46.534 | 46.605 | **44.391** | 96.648 | 3220.521 |

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
| _(floor: empty program)_ | _3.049_ | _91.666_ | _**94.715**_ | _65.441_ | _69.435_ |
| `lcg` | 3.175 | 101.120 | **104.295** | 77.777 | 77.489 |
| `packet_classifier` | 3.121 | 95.374 | **98.495** | 74.017 | 75.541 |
| `ring_write` | 3.264 | 99.499 | **102.763** | 78.006 | 79.132 |
| `histogram_bins` | 3.327 | 101.269 | **104.596** | 79.899 | 79.794 |
| `prefix_scan` | 3.418 | 103.250 | **106.668** | 80.755 | 78.116 |
| `binary_search` | 3.500 | 101.905 | **105.405** | 77.727 | 81.653 |
| `sort_window` | 3.511 | 110.610 | **114.121** | 85.591 | 87.422 |
| `bloom_filter` | 3.732 | 107.086 | **110.818** | 84.084 | 84.485 |
| `hash_join` | 5.824 | 212.391 | **218.215** | 125.054 | 118.566 |
| `sieve` | 3.360 | 102.688 | **106.048** | 85.202 | 86.843 |
| `fib` | 3.077 | 97.456 | **100.533** | 75.350 | 73.756 |
| `collatz` | 3.248 | 98.897 | **102.145** | 76.329 | 77.243 |
| `matmul` | 3.592 | 106.146 | **109.738** | 87.737 | 100.816 |
| `json_parse` | 39.799 | 500.296 | **540.095** | 127.928 | 193.985 |
| `nbody` | 4.590 | 120.219 | **124.809** | 105.446 | 105.195 |

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
