# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T03:25:20Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `f828432bac9a089d7eeeb99f4b985955a347834c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31144058386 |
| NURL | `v0.34.0` |
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
| _(floor: empty program)_ | _1.649_ | _1.749_ | _1.864_ | _23.075_ | _17.403_ |
| `lcg` | **39.293** | 39.384 | 39.544 | 1880.876 | 5149.963 |
| `packet_classifier` | **56.679** | 56.718 | 56.762 | 163.286 | 4381.508 |
| `ring_write` | **42.494** | 42.609 | 42.839 | 66.590 | 6222.497 |
| `histogram_bins` | **39.931** | 41.575 | 39.984 | 66.213 | 6027.614 |
| `prefix_scan` | **21.869** | 21.986 | 22.146 | 65.476 | 4502.699 |
| `binary_search` | 39.969 | **38.514** | 43.322 | 105.124 | 5999.525 |
| `sort_window` | 27.355 | 27.479 | **26.968** | 197.346 | 11480.104 |
| `bloom_filter` | **18.081** | 18.273 | 18.601 | 2874.802 | 7287.275 |
| `hash_join` | **28.107** | 30.387 | 30.084 | 3422.517 | 8290.738 |
| `sieve` | 20.506 | 18.139 | **18.071** | 65.173 | 3441.948 |
| `fib` | **25.341** | 30.070 | 28.272 | 130.701 | 1354.534 |
| `collatz` | 12.472 | **12.445** | 12.571 | 48.959 | 712.619 |
| `matmul` | **33.435** | 33.651 | 33.940 | 75.763 | 3190.954 |
| `json_parse` | **8.773** | 8.889 | 11.765 | 35.134 | 37.104 |
| `nbody` | 40.873 | 41.017 | **39.339** | 100.782 | 3008.966 |

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
| _(floor: empty program)_ | _2.597_ | _80.334_ | _**82.931**_ | _58.192_ | _61.792_ |
| `lcg` | 2.729 | 86.771 | **89.500** | 67.088 | 66.802 |
| `packet_classifier` | 2.878 | 89.799 | **92.677** | 68.864 | 67.522 |
| `ring_write` | 2.937 | 90.029 | **92.966** | 70.230 | 68.847 |
| `histogram_bins` | 2.971 | 92.867 | **95.838** | 71.017 | 72.668 |
| `prefix_scan` | 3.004 | 94.326 | **97.330** | 73.845 | 71.855 |
| `binary_search` | 3.082 | 89.751 | **92.833** | 68.393 | 73.396 |
| `sort_window` | 3.142 | 99.099 | **102.241** | 75.331 | 77.635 |
| `bloom_filter` | 3.323 | 97.945 | **101.268** | 76.298 | 74.439 |
| `hash_join` | 5.338 | 209.502 | **214.840** | 118.603 | 108.066 |
| `sieve` | 2.994 | 90.721 | **93.715** | 76.667 | 77.567 |
| `fib` | 2.723 | 83.656 | **86.379** | 65.262 | 66.319 |
| `collatz` | 2.896 | 87.296 | **90.192** | 66.316 | 68.581 |
| `matmul` | 3.247 | 99.336 | **102.583** | 79.671 | 90.868 |
| `json_parse` | 39.142 | 512.681 | **551.823** | 124.485 | 175.205 |
| `nbody` | 4.239 | 106.532 | **110.771** | 96.581 | 91.671 |

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
