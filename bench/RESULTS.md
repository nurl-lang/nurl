# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-10T20:48:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e49beb01e25ab7cd4d2fa0a04ecd24dabbd88ade` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31430385403 |
| NURL | `v0.36.0-75-ge49beb01` |
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
| _(floor: empty program)_ | _1.665_ | _1.720_ | _1.892_ | _23.213_ | _17.040_ |
| `lcg` | 39.685 | **39.390** | 39.689 | 1884.275 | 5091.228 |
| `packet_classifier` | **56.717** | 56.773 | 56.836 | 163.072 | 4440.313 |
| `ring_write` | **42.493** | 42.718 | 42.703 | 66.372 | 6141.769 |
| `histogram_bins` | **39.779** | 41.614 | 40.065 | 67.432 | 5871.783 |
| `prefix_scan` | **21.967** | 22.007 | 22.232 | 65.836 | 4550.189 |
| `binary_search` | 40.094 | **38.507** | 43.468 | 107.256 | 5941.502 |
| `sort_window` | 27.550 | 27.548 | **27.036** | 198.701 | 11711.833 |
| `bloom_filter` | **18.045** | 18.463 | 18.608 | 2903.157 | 7603.570 |
| `hash_join` | **28.264** | 30.243 | 30.187 | 3449.143 | 8282.434 |
| `sieve` | 20.530 | 20.503 | **20.334** | 67.539 | 3167.204 |
| `fib` | **25.382** | 30.099 | 28.333 | 131.978 | 1391.787 |
| `collatz` | **12.507** | 12.519 | 12.537 | 50.000 | 713.794 |
| `matmul` | **33.762** | 34.030 | 34.102 | 77.588 | 3486.934 |
| `json_parse` | 42.474 | **8.938** | 11.898 | 35.635 | 38.263 |
| `nbody` | 41.220 | 41.080 | **40.429** | 102.142 | 3186.992 |

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
| _(floor: empty program)_ | _2.737_ | _82.821_ | _**85.558**_ | _60.277_ | _62.325_ |
| `lcg` | 2.820 | 87.838 | **90.658** | 68.816 | 71.375 |
| `packet_classifier` | 2.873 | 89.233 | **92.106** | 71.246 | 70.290 |
| `ring_write` | 2.987 | 90.819 | **93.806** | 72.212 | 72.275 |
| `histogram_bins` | 3.049 | 93.175 | **96.224** | 70.935 | 74.091 |
| `prefix_scan` | 3.120 | 92.437 | **95.557** | 72.662 | 81.194 |
| `binary_search` | 3.178 | 93.382 | **96.560** | 71.262 | 75.697 |
| `sort_window` | 3.215 | 98.242 | **101.457** | 75.414 | 79.573 |
| `bloom_filter` | 3.371 | 97.996 | **101.367** | 76.546 | 77.195 |
| `hash_join` | 5.568 | 214.474 | **220.042** | 121.500 | 113.298 |
| `sieve` | 3.037 | 92.182 | **95.219** | 79.811 | 80.100 |
| `fib` | 2.885 | 86.447 | **89.332** | 65.558 | 69.318 |
| `collatz` | 2.969 | 89.743 | **92.712** | 69.554 | 70.666 |
| `matmul` | 3.273 | 99.680 | **102.953** | 83.612 | 92.605 |
| `json_parse` | 41.949 | 548.057 | **590.006** | 125.548 | 185.172 |
| `nbody` | 4.377 | 108.161 | **112.538** | 99.214 | 97.183 |

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
