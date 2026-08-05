# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T18:13:12Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1dc7554247e65515cf2b25e1e328d75a3984be9d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31033297477 |
| NURL | `v0.33.0-25-g1dc75542` |
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
| _(floor: empty program)_ | _1.796_ | _1.899_ | _2.032_ | _27.484_ | _17.940_ |
| `lcg` | **44.345** | 44.437 | 44.583 | 1834.888 | 5315.771 |
| `packet_classifier` | **63.725** | 63.841 | 63.944 | 155.607 | 4610.947 |
| `ring_write` | 47.877 | **47.851** | 48.055 | 74.272 | 6932.029 |
| `histogram_bins` | **44.987** | 45.104 | 45.150 | 76.570 | 7135.572 |
| `prefix_scan` | **24.846** | 24.899 | 25.141 | 73.484 | 4862.905 |
| `binary_search` | **35.787** | 36.073 | 46.097 | 113.903 | 6311.253 |
| `sort_window` | 30.939 | **30.906** | 30.919 | 166.124 | 12396.801 |
| `bloom_filter` | **20.042** | 20.782 | 20.945 | 2825.502 | 7966.464 |
| `hash_join` | **29.439** | 30.974 | 31.309 | 3452.213 | 8139.508 |
| `sieve` | 20.792 | **20.351** | 20.752 | 70.696 | 3758.097 |
| `fib` | **28.307** | 33.768 | 29.833 | 143.482 | 1289.292 |
| `collatz` | **13.911** | 13.939 | 14.055 | 51.859 | 750.611 |
| `matmul` | **45.649** | 46.635 | 46.582 | 84.073 | 3326.688 |
| `json_parse` | **8.643** | 9.145 | 12.354 | 38.781 | 37.560 |
| `nbody` | 46.284 | 46.406 | **44.216** | 98.753 | 3297.052 |

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
| _(floor: empty program)_ | _3.100_ | _94.863_ | _**97.963**_ | _66.244_ | _66.403_ |
| `lcg` | 3.077 | 95.497 | **98.574** | 73.518 | 74.334 |
| `packet_classifier` | 3.119 | 97.372 | **100.491** | 74.475 | 74.423 |
| `ring_write` | 3.268 | 99.168 | **102.436** | 75.898 | 75.464 |
| `histogram_bins` | 3.324 | 102.096 | **105.420** | 77.286 | 78.142 |
| `prefix_scan` | 3.401 | 107.765 | **111.166** | 83.507 | 80.770 |
| `binary_search` | 3.583 | 106.369 | **109.952** | 79.673 | 81.066 |
| `sort_window` | 3.535 | 109.620 | **113.155** | 83.957 | 85.095 |
| `bloom_filter` | 3.678 | 105.761 | **109.439** | 81.245 | 82.551 |
| `hash_join` | 5.841 | 215.862 | **221.703** | 125.999 | 120.604 |
| `sieve` | 3.346 | 103.281 | **106.627** | 82.476 | 85.939 |
| `fib` | 3.103 | 97.145 | **100.248** | 75.762 | 75.545 |
| `collatz` | 3.339 | 102.041 | **105.380** | 77.065 | 77.701 |
| `matmul` | 3.588 | 109.261 | **112.849** | 89.489 | 106.547 |
| `json_parse` | 41.068 | 511.146 | **552.214** | 126.001 | 188.076 |
| `nbody` | 4.666 | 116.821 | **121.487** | 100.207 | 101.125 |

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
