# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T18:53:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372444 KiB |
| Commit | `cba2ffab2cd1aa8652412178cd85c88f6b81fefe` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30656708263 |
| NURL | `v0.29.0-96-gcba2ffa` |
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
| _(floor: empty program)_ | _1.270_ | _1.319_ | _1.389_ | _19.063_ | _14.116_ |
| `lcg` | 35.610 | **35.590** | 35.688 | 1334.200 | 3857.048 |
| `packet_classifier` | **58.154** | 63.448 | 62.095 | 151.837 | 3152.193 |
| `ring_write` | 39.900 | **39.729** | 40.138 | 58.964 | 4500.659 |
| `histogram_bins` | 36.795 | **36.701** | 36.814 | 59.445 | 4644.045 |
| `prefix_scan` | **19.905** | 20.168 | 20.191 | 58.662 | 3349.564 |
| `binary_search` | 30.535 | **27.966** | 39.934 | 98.493 | 4712.934 |
| `sort_window` | 36.482 | 45.572 | **35.728** | 158.500 | 10091.396 |
| `bloom_filter` | **12.603** | 12.760 | 13.026 | 2127.667 | 6025.458 |
| `hash_join` | **21.735** | 23.457 | 23.944 | 2672.461 | 6230.699 |
| `sieve` | 33.869 | 32.842 | **32.759** | 75.942 | 2410.216 |
| `fib` | 24.939 | 26.802 | **22.941** | 99.575 | 786.154 |
| `collatz` | **13.270** | 13.591 | 14.049 | 52.569 | 501.190 |
| `matmul` | **17.958** | 18.122 | 17.986 | 65.147 | 2209.714 |
| `json_parse` | **6.387** | 6.915 | 8.655 | 28.109 | 29.577 |
| `nbody` | **28.881** | 29.100 | 30.803 | 72.244 | 1910.756 |

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
| _(floor: empty program)_ | _2.442_ | _62.931_ | _**65.373**_ | _44.539_ | _52.840_ |
| `lcg` | 2.166 | 62.873 | **65.039** | 47.698 | 58.413 |
| `packet_classifier` | 2.305 | 69.356 | **71.661** | 53.533 | 58.635 |
| `ring_write` | 2.387 | 67.442 | **69.829** | 52.607 | 60.772 |
| `histogram_bins` | 2.459 | 69.779 | **72.238** | 50.648 | 61.850 |
| `prefix_scan` | 2.637 | 76.336 | **78.973** | 58.472 | 64.059 |
| `binary_search` | 2.716 | 67.903 | **70.619** | 49.896 | 65.342 |
| `sort_window` | 2.860 | 74.553 | **77.413** | 57.760 | 68.744 |
| `bloom_filter` | 2.890 | 70.246 | **73.136** | 56.636 | 62.043 |
| `hash_join` | 5.926 | 161.142 | **167.068** | 181.204 | 95.845 |
| `sieve` | 2.520 | 67.540 | **70.060** | 56.816 | 69.138 |
| `fib` | 2.234 | 65.107 | **67.341** | 48.517 | 57.122 |
| `collatz` | 2.456 | 67.951 | **70.407** | 49.684 | 60.538 |
| `matmul` | 3.030 | 70.400 | **73.430** | 58.885 | 79.974 |
| `json_parse` | 47.092 | 564.172 | **611.264** | 94.519 | 164.031 |
| `nbody` | 4.095 | 79.209 | **83.304** | 71.534 | 78.921 |

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
