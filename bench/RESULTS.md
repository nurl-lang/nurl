# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T20:04:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `fad6c025dd82069043dfa30f42e9103c668a0ba1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31213905642 |
| NURL | `v0.35.1` |
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
| _(floor: empty program)_ | _1.652_ | _1.702_ | _1.860_ | _22.849_ | _17.010_ |
| `lcg` | **39.216** | 39.270 | 39.396 | 1872.914 | 5191.595 |
| `packet_classifier` | **56.422** | 56.458 | 56.499 | 161.856 | 4413.572 |
| `ring_write` | **42.296** | 42.438 | 42.451 | 66.144 | 6201.645 |
| `histogram_bins` | **39.730** | 42.029 | 39.957 | 64.979 | 6027.450 |
| `prefix_scan` | **21.797** | 21.946 | 22.062 | 64.245 | 4538.600 |
| `binary_search` | 39.738 | **38.367** | 43.170 | 106.049 | 6492.155 |
| `sort_window` | 27.322 | 27.491 | **26.870** | 197.054 | 11363.555 |
| `bloom_filter` | **18.046** | 18.277 | 18.457 | 2807.814 | 7514.478 |
| `hash_join` | **28.122** | 30.256 | 30.207 | 3468.276 | 8295.823 |
| `sieve` | **18.489** | 18.523 | 20.001 | 65.532 | 3208.537 |
| `fib` | **25.390** | 30.094 | 28.381 | 131.245 | 1374.209 |
| `collatz` | **12.460** | 12.493 | 12.529 | 48.164 | 714.279 |
| `matmul` | 33.940 | **33.541** | 33.745 | 74.710 | 3144.676 |
| `json_parse` | **8.806** | 8.911 | 11.822 | 35.939 | 38.264 |
| `nbody` | 40.857 | 40.920 | **39.140** | 102.173 | 3124.065 |

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
| _(floor: empty program)_ | _2.630_ | _79.349_ | _**81.979**_ | _56.093_ | _60.477_ |
| `lcg` | 2.724 | 83.802 | **86.526** | 64.436 | 68.638 |
| `packet_classifier` | 2.782 | 86.587 | **89.369** | 66.271 | 67.075 |
| `ring_write` | 2.925 | 86.801 | **89.726** | 68.058 | 69.700 |
| `histogram_bins` | 2.982 | 90.041 | **93.023** | 70.381 | 72.592 |
| `prefix_scan` | 2.990 | 90.281 | **93.271** | 71.781 | 70.479 |
| `binary_search` | 3.106 | 89.523 | **92.629** | 67.813 | 93.357 |
| `sort_window` | 3.131 | 98.228 | **101.359** | 75.990 | 77.070 |
| `bloom_filter` | 3.306 | 95.607 | **98.913** | 74.784 | 73.546 |
| `hash_join` | 5.327 | 211.613 | **216.940** | 119.384 | 109.553 |
| `sieve` | 3.007 | 93.862 | **96.869** | 79.420 | 77.959 |
| `fib` | 2.716 | 83.667 | **86.383** | 66.829 | 67.294 |
| `collatz` | 2.949 | 89.148 | **92.097** | 67.696 | 69.312 |
| `matmul` | 3.260 | 95.228 | **98.488** | 78.850 | 99.506 |
| `json_parse` | 39.212 | 521.354 | **560.566** | 122.281 | 177.853 |
| `nbody` | 4.301 | 111.142 | **115.443** | 100.824 | 91.303 |

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
