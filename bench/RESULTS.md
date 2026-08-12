# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-12T16:07:23Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a3bb9eb6d411ba9addc6cf223cbc07299462e56c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31615570335 |
| NURL | `v0.39.0-12-ga3bb9eb6` |
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
| _(floor: empty program)_ | _1.799_ | _1.893_ | _2.012_ | _24.890_ | _17.956_ |
| `lcg` | **44.314** | 44.426 | 44.676 | 1836.409 | 5530.952 |
| `packet_classifier` | **63.732** | 63.785 | 63.852 | 158.862 | 4602.747 |
| `ring_write` | **47.772** | 47.865 | 47.934 | 72.662 | 6522.260 |
| `histogram_bins` | **44.828** | 44.870 | 45.034 | 75.730 | 6319.087 |
| `prefix_scan` | **24.628** | 24.657 | 24.889 | 71.112 | 4990.987 |
| `binary_search` | **35.945** | 35.985 | 46.147 | 112.823 | 6611.191 |
| `sort_window` | 30.895 | 31.026 | **30.379** | 173.523 | 11143.081 |
| `bloom_filter` | **19.922** | 20.580 | 20.917 | 2780.590 | 7498.571 |
| `hash_join` | **29.368** | 30.825 | 31.323 | 3456.983 | 8303.574 |
| `sieve` | 20.640 | **20.370** | 20.462 | 72.405 | 3364.022 |
| `fib` | **28.081** | 33.546 | 29.573 | 143.801 | 1282.579 |
| `collatz` | **13.939** | 13.993 | 14.091 | 52.356 | 754.691 |
| `matmul` | 46.612 | **45.969** | 46.044 | 85.716 | 3329.044 |
| `json_parse` | **9.016** | 9.488 | 12.861 | 41.433 | 40.147 |
| `nbody` | 46.594 | 46.660 | **44.442** | 100.472 | 3169.497 |

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
| _(floor: empty program)_ | _3.149_ | _90.238_ | _**93.387**_ | _66.151_ | _66.726_ |
| `lcg` | 3.219 | 95.495 | **98.714** | 74.818 | 74.188 |
| `packet_classifier` | 3.231 | 96.518 | **99.749** | 76.727 | 74.346 |
| `ring_write` | 3.345 | 96.828 | **100.173** | 75.880 | 74.310 |
| `histogram_bins` | 3.411 | 101.704 | **105.115** | 79.083 | 78.012 |
| `prefix_scan` | 3.504 | 102.324 | **105.828** | 79.808 | 77.736 |
| `binary_search` | 3.582 | 101.254 | **104.836** | 76.501 | 80.103 |
| `sort_window` | 3.631 | 108.403 | **112.034** | 82.716 | 87.015 |
| `bloom_filter` | 3.798 | 108.320 | **112.118** | 83.032 | 81.536 |
| `hash_join` | 6.088 | 215.270 | **221.358** | 122.929 | 115.479 |
| `sieve` | 3.444 | 104.993 | **108.437** | 86.298 | 86.316 |
| `fib` | 3.199 | 95.421 | **98.620** | 73.841 | 73.192 |
| `collatz` | 3.402 | 97.690 | **101.092** | 74.472 | 76.246 |
| `matmul` | 3.721 | 111.219 | **114.940** | 89.386 | 102.347 |
| `json_parse` | 45.494 | 544.487 | **589.981** | 132.177 | 197.928 |
| `nbody` | 4.966 | 122.444 | **127.410** | 105.311 | 104.567 |

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
