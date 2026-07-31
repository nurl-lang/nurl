# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T20:49:31Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `64195f4e6054dfb8169742ec32e0a55e66c85f8c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30663999621 |
| NURL | `v0.30.0` |
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
| _(floor: empty program)_ | _1.671_ | _1.712_ | _1.846_ | _23.228_ | _16.964_ |
| `lcg` | **39.255** | 39.369 | 39.435 | 1874.666 | 5111.613 |
| `packet_classifier` | **56.358** | 56.478 | 56.586 | 163.076 | 4359.769 |
| `ring_write` | **42.316** | 42.483 | 42.543 | 66.364 | 6252.127 |
| `histogram_bins` | **39.814** | 41.412 | 39.905 | 66.380 | 6240.668 |
| `prefix_scan` | **21.870** | 21.941 | 22.073 | 65.755 | 4660.475 |
| `binary_search` | 39.651 | **38.522** | 43.162 | 106.650 | 6308.000 |
| `sort_window` | 27.401 | 27.430 | **27.050** | 198.099 | 11245.667 |
| `bloom_filter` | **18.049** | 18.284 | 18.426 | 2846.368 | 7378.048 |
| `hash_join` | **28.122** | 30.415 | 30.339 | 3453.332 | 8390.613 |
| `sieve` | 20.990 | 20.764 | **20.366** | 67.524 | 3326.180 |
| `fib` | **25.406** | 30.181 | 28.516 | 134.664 | 1381.705 |
| `collatz` | **12.490** | 12.645 | 12.882 | 52.182 | 722.199 |
| `matmul` | **33.704** | 33.952 | 33.897 | 76.014 | 3642.083 |
| `json_parse` | **8.615** | 8.896 | 11.799 | 34.612 | 38.238 |
| `nbody` | 40.915 | 40.939 | **39.088** | 99.931 | 3091.341 |

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
| _(floor: empty program)_ | _2.854_ | _80.917_ | _**83.771**_ | _57.737_ | _60.510_ |
| `lcg` | 2.884 | 84.862 | **87.746** | 67.002 | 68.344 |
| `packet_classifier` | 2.882 | 85.015 | **87.897** | 68.603 | 69.906 |
| `ring_write` | 3.031 | 87.156 | **90.187** | 68.137 | 69.845 |
| `histogram_bins` | 3.158 | 96.260 | **99.418** | 73.822 | 72.357 |
| `prefix_scan` | 3.130 | 91.907 | **95.037** | 72.823 | 71.826 |
| `binary_search` | 3.369 | 91.434 | **94.803** | 68.884 | 75.283 |
| `sort_window` | 3.410 | 98.818 | **102.228** | 77.704 | 79.496 |
| `bloom_filter` | 3.729 | 95.016 | **98.745** | 76.347 | 75.124 |
| `hash_join` | 6.808 | 213.954 | **220.762** | 123.383 | 113.440 |
| `sieve` | 3.161 | 94.549 | **97.710** | 80.299 | 79.419 |
| `fib` | 2.875 | 87.935 | **90.810** | 69.003 | 69.577 |
| `collatz` | 3.020 | 91.207 | **94.227** | 71.079 | 70.912 |
| `matmul` | 3.560 | 100.371 | **103.931** | 83.727 | 95.141 |
| `json_parse` | 54.101 | 524.300 | **578.401** | 128.869 | 178.376 |
| `nbody` | 4.992 | 106.931 | **111.923** | 96.971 | 96.924 |

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
