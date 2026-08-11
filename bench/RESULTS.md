# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T22:42:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `5ddb2a5a01049296c5a1fe3e0596c2c0be2bc559` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31543224092 |
| NURL | `v0.38.0-15-g5ddb2a5a` |
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
| _(floor: empty program)_ | _1.730_ | _1.744_ | _1.929_ | _23.968_ | _18.298_ |
| `lcg` | **39.459** | 39.517 | 39.598 | 1891.125 | 5047.204 |
| `packet_classifier` | **56.655** | 56.672 | 56.842 | 162.989 | 4490.724 |
| `ring_write` | **42.563** | 42.629 | 42.794 | 68.433 | 6313.184 |
| `histogram_bins` | **39.753** | 41.494 | 40.093 | 66.972 | 5943.854 |
| `prefix_scan` | **22.098** | 22.121 | 22.180 | 65.920 | 4710.017 |
| `binary_search` | 40.085 | **38.536** | 43.364 | 107.411 | 6048.277 |
| `sort_window` | 27.544 | 27.686 | **27.175** | 198.829 | 11538.485 |
| `bloom_filter` | **18.232** | 18.429 | 18.646 | 2852.428 | 7711.449 |
| `hash_join` | **28.024** | 30.179 | 30.036 | 3442.181 | 8659.139 |
| `sieve` | 20.776 | **20.142** | 20.368 | 68.910 | 3198.249 |
| `fib` | **25.589** | 31.110 | 28.606 | 133.727 | 1339.056 |
| `collatz` | 12.645 | **12.642** | 12.777 | 51.235 | 712.241 |
| `matmul` | **33.805** | 33.940 | 34.189 | 77.600 | 3217.860 |
| `json_parse` | 9.013 | **8.910** | 11.861 | 36.720 | 38.326 |
| `nbody` | 41.281 | 41.221 | **39.248** | 100.323 | 3184.384 |

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
| _(floor: empty program)_ | _2.779_ | _83.744_ | _**86.523**_ | _59.235_ | _62.068_ |
| `lcg` | 2.882 | 90.893 | **93.775** | 69.458 | 70.102 |
| `packet_classifier` | 2.948 | 90.437 | **93.385** | 72.553 | 73.676 |
| `ring_write` | 3.067 | 91.749 | **94.816** | 71.864 | 71.476 |
| `histogram_bins` | 3.069 | 94.142 | **97.211** | 71.642 | 71.894 |
| `prefix_scan` | 3.108 | 94.550 | **97.658** | 73.930 | 74.129 |
| `binary_search` | 3.262 | 95.757 | **99.019** | 71.658 | 75.855 |
| `sort_window` | 3.352 | 101.960 | **105.312** | 80.193 | 81.915 |
| `bloom_filter` | 3.543 | 99.797 | **103.340** | 78.002 | 80.503 |
| `hash_join` | 5.695 | 215.758 | **221.453** | 121.615 | 112.315 |
| `sieve` | 3.115 | 95.098 | **98.213** | 80.777 | 80.368 |
| `fib` | 2.844 | 88.353 | **91.197** | 68.920 | 68.806 |
| `collatz` | 3.064 | 93.337 | **96.401** | 70.456 | 71.206 |
| `matmul` | 3.342 | 99.430 | **102.772** | 81.075 | 93.019 |
| `json_parse` | 45.112 | 550.227 | **595.339** | 128.586 | 181.928 |
| `nbody` | 4.679 | 113.294 | **117.973** | 102.013 | 94.583 |

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
