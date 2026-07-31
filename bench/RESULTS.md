# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T05:54:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e5092e569f8187bc38ce3127287c7e3379be45b8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30607851514 |
| NURL | `v0.29.0-74-ge5092e5` |
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
| _(floor: empty program)_ | _1.664_ | _1.717_ | _1.838_ | _22.521_ | _17.305_ |
| `lcg` | 39.369 | **39.350** | 39.506 | 1876.471 | 5102.131 |
| `packet_classifier` | **56.594** | 56.706 | 56.759 | 162.594 | 4326.509 |
| `ring_write` | **42.541** | 42.677 | 42.831 | 67.683 | 7040.527 |
| `histogram_bins` | **39.900** | 41.589 | 40.108 | 67.483 | 6459.291 |
| `prefix_scan` | **21.902** | 21.944 | 21.981 | 65.647 | 4593.379 |
| `binary_search` | 40.092 | **38.647** | 43.554 | 108.136 | 6184.849 |
| `sort_window` | 27.630 | 27.707 | **27.144** | 197.282 | 11837.547 |
| `bloom_filter` | **18.222** | 18.384 | 18.796 | 2834.034 | 7416.948 |
| `hash_join` | **28.486** | 30.421 | 30.244 | 3410.383 | 8176.975 |
| `sieve` | 20.263 | 19.912 | **17.994** | 65.873 | 3271.904 |
| `fib` | **25.407** | 30.219 | 28.575 | 134.136 | 1358.868 |
| `collatz` | **12.462** | 12.499 | 12.653 | 50.047 | 709.178 |
| `matmul` | 33.917 | **33.890** | 33.980 | 78.530 | 3258.484 |
| `json_parse` | **8.531** | 8.847 | 11.736 | 34.809 | 37.226 |
| `nbody` | 40.931 | 40.912 | **39.021** | 99.953 | 3119.086 |

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
| _(floor: empty program)_ | _2.899_ | _79.966_ | _**82.865**_ | _57.765_ | _61.339_ |
| `lcg` | 3.141 | 86.386 | **89.527** | 68.822 | 70.060 |
| `packet_classifier` | 3.289 | 88.574 | **91.863** | 69.104 | 70.502 |
| `ring_write` | 3.561 | 88.592 | **92.153** | 70.306 | 70.569 |
| `histogram_bins` | 3.675 | 94.845 | **98.520** | 74.359 | 73.987 |
| `prefix_scan` | 3.697 | 91.706 | **95.403** | 71.678 | 73.246 |
| `binary_search` | 3.880 | 90.899 | **94.779** | 70.281 | 75.217 |
| `sort_window` | 4.096 | 101.286 | **105.382** | 79.860 | 81.894 |
| `bloom_filter` | 4.330 | 100.093 | **104.423** | 80.234 | 78.202 |
| `hash_join` | 8.845 | 213.658 | **222.503** | 122.117 | 113.375 |
| `sieve` | 3.697 | 92.800 | **96.497** | 77.023 | 78.421 |
| `fib` | 3.182 | 85.851 | **89.033** | 66.261 | 69.096 |
| `collatz` | 3.462 | 87.368 | **90.830** | 67.064 | 70.413 |
| `matmul` | 4.329 | 95.700 | **100.029** | 82.108 | 92.161 |
| `json_parse` | 73.733 | 721.343 | **795.076** | 122.428 | 181.206 |
| `nbody` | 6.617 | 107.239 | **113.856** | 97.163 | 94.179 |

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
