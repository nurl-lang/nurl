# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T07:56:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377692 KiB |
| Commit | `3725cf19475fe1b83327eb6489b84cde2a90e18a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30690567054 |
| NURL | `v0.30.0-8-g3725cf1` |
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
| _(floor: empty program)_ | _1.667_ | _1.744_ | _1.879_ | _23.573_ | _16.898_ |
| `lcg` | 39.248 | **39.185** | 39.423 | 1882.298 | 5195.063 |
| `packet_classifier` | 56.630 | **56.591** | 56.994 | 163.668 | 4529.214 |
| `ring_write` | **42.286** | 42.355 | 42.529 | 65.128 | 6582.122 |
| `histogram_bins` | **39.602** | 41.345 | 39.786 | 67.041 | 6356.429 |
| `prefix_scan` | 21.904 | **21.892** | 21.994 | 66.250 | 4457.304 |
| `binary_search` | 39.983 | **38.472** | 43.305 | 106.871 | 6118.228 |
| `sort_window` | 27.414 | 27.479 | **26.941** | 197.497 | 12360.135 |
| `bloom_filter` | **18.065** | 18.206 | 18.473 | 2849.543 | 7549.442 |
| `hash_join` | **28.067** | 30.263 | 30.117 | 3412.319 | 8213.432 |
| `sieve` | 20.785 | **20.123** | 20.268 | 66.601 | 3184.653 |
| `fib` | **25.304** | 29.969 | 28.334 | 131.420 | 1347.918 |
| `collatz` | **12.426** | 12.442 | 12.513 | 48.778 | 715.002 |
| `matmul` | **33.515** | 33.533 | 33.709 | 74.742 | 3401.477 |
| `json_parse` | **8.660** | 8.813 | 11.698 | 35.568 | 37.110 |
| `nbody` | 41.148 | 40.992 | **39.091** | 100.177 | 3113.825 |

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
| _(floor: empty program)_ | _2.686_ | _79.718_ | _**82.404**_ | _60.128_ | _62.541_ |
| `lcg` | 2.826 | 87.531 | **90.357** | 71.173 | 67.110 |
| `packet_classifier` | 2.799 | 86.912 | **89.711** | 70.359 | 70.024 |
| `ring_write` | 2.903 | 88.170 | **91.073** | 83.532 | 68.041 |
| `histogram_bins` | 2.902 | 90.133 | **93.035** | 70.671 | 70.745 |
| `prefix_scan` | 2.986 | 91.608 | **94.594** | 72.844 | 70.590 |
| `binary_search` | 3.106 | 91.161 | **94.267** | 70.326 | 73.950 |
| `sort_window` | 3.222 | 98.486 | **101.708** | 80.440 | 78.974 |
| `bloom_filter` | 3.360 | 96.654 | **100.014** | 78.088 | 75.483 |
| `hash_join` | 5.297 | 208.593 | **213.890** | 122.110 | 109.463 |
| `sieve` | 2.970 | 90.773 | **93.743** | 79.035 | 85.804 |
| `fib` | 2.749 | 85.702 | **88.451** | 66.047 | 66.917 |
| `collatz` | 2.904 | 89.600 | **92.504** | 71.147 | 71.000 |
| `matmul` | 3.264 | 97.712 | **100.976** | 81.166 | 91.205 |
| `json_parse` | 39.922 | 518.696 | **558.618** | 122.508 | 176.509 |
| `nbody` | 4.303 | 108.034 | **112.337** | 96.505 | 92.987 |

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
