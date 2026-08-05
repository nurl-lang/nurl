# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T22:58:06Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `9a71da2f4cdeb4543281bc0226058a38e58705df` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31054409653 |
| NURL | `v0.33.0-41-g9a71da2f` |
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
| _(floor: empty program)_ | _1.674_ | _1.723_ | _1.877_ | _22.556_ | _17.222_ |
| `lcg` | **39.383** | 39.423 | 39.540 | 1913.010 | 5338.197 |
| `packet_classifier` | 56.745 | **56.682** | 56.856 | 164.473 | 4328.718 |
| `ring_write` | **42.558** | 42.706 | 42.770 | 69.590 | 6343.041 |
| `histogram_bins` | **39.770** | 41.429 | 39.873 | 67.658 | 5919.890 |
| `prefix_scan` | **22.120** | 22.187 | 22.366 | 67.142 | 4607.602 |
| `binary_search` | 40.002 | **38.611** | 43.647 | 107.971 | 5954.220 |
| `sort_window` | 27.715 | 27.539 | **27.124** | 197.835 | 12022.612 |
| `bloom_filter` | **18.123** | 18.360 | 18.565 | 2837.633 | 8073.496 |
| `hash_join` | **28.179** | 30.317 | 30.165 | 3429.068 | 8248.269 |
| `sieve` | 19.044 | 18.385 | **18.379** | 66.256 | 3276.794 |
| `fib` | **25.524** | 29.988 | 28.347 | 132.698 | 1342.155 |
| `collatz` | **12.581** | 12.628 | 12.781 | 51.612 | 711.611 |
| `matmul` | **33.874** | 33.977 | 34.008 | 76.211 | 3178.239 |
| `json_parse` | **8.849** | 9.070 | 12.011 | 37.980 | 39.016 |
| `nbody` | 41.216 | 41.170 | **39.318** | 99.958 | 3116.789 |

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
| _(floor: empty program)_ | _2.614_ | _83.505_ | _**86.119**_ | _59.895_ | _61.069_ |
| `lcg` | 2.742 | 88.988 | **91.730** | 69.303 | 69.111 |
| `packet_classifier` | 2.844 | 89.187 | **92.031** | 69.843 | 68.662 |
| `ring_write` | 2.977 | 91.756 | **94.733** | 70.335 | 69.435 |
| `histogram_bins` | 3.078 | 97.273 | **100.351** | 74.621 | 72.925 |
| `prefix_scan` | 3.160 | 98.877 | **102.037** | 77.032 | 73.306 |
| `binary_search` | 3.147 | 95.618 | **98.765** | 70.854 | 74.526 |
| `sort_window` | 3.238 | 102.905 | **106.143** | 80.279 | 81.218 |
| `bloom_filter` | 3.351 | 97.182 | **100.533** | 78.458 | 76.149 |
| `hash_join` | 5.436 | 216.306 | **221.742** | 123.815 | 112.597 |
| `sieve` | 3.054 | 96.912 | **99.966** | 80.388 | 80.065 |
| `fib` | 2.732 | 86.973 | **89.705** | 68.096 | 68.025 |
| `collatz` | 2.937 | 92.511 | **95.448** | 69.844 | 70.213 |
| `matmul` | 3.258 | 99.381 | **102.639** | 81.977 | 92.172 |
| `json_parse` | 41.121 | 530.977 | **572.098** | 128.905 | 183.241 |
| `nbody` | 4.307 | 114.352 | **118.659** | 100.951 | 95.212 |

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
