# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-29T23:12:26Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377740 KiB |
| Commit | `f152f990677b27076094f99ea561a1ddc01d3615` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30498505817 |
| NURL | `v0.29.0` |
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
| _(floor: empty program)_ | _1.655_ | _1.699_ | _1.853_ | _22.621_ | _16.794_ |
| `lcg` | **39.089** | 39.209 | 39.286 | 1872.162 | 5150.385 |
| `packet_classifier` | **56.337** | 56.377 | 56.593 | 160.335 | 4400.252 |
| `ring_write` | **42.273** | 42.315 | 42.494 | 64.337 | 6210.660 |
| `histogram_bins` | **39.625** | 41.368 | 39.762 | 65.190 | 5944.817 |
| `prefix_scan` | **21.862** | 21.885 | 22.055 | 64.114 | 4499.807 |
| `binary_search` | 39.875 | **38.503** | 43.358 | 106.548 | 6290.147 |
| `sort_window` | 27.343 | 27.367 | **26.915** | 196.703 | 11639.996 |
| `bloom_filter` | **17.943** | 18.178 | 18.464 | 2808.945 | 7522.975 |
| `hash_join` | **28.057** | 30.309 | 29.926 | 3473.079 | 8158.196 |
| `sieve` | 18.368 | **17.975** | 18.039 | 65.811 | 3383.464 |
| `fib` | **25.374** | 30.097 | 28.285 | 131.945 | 1347.186 |
| `collatz` | 12.471 | **12.355** | 12.525 | 48.436 | 720.136 |
| `matmul` | 33.735 | **33.650** | 33.840 | 75.094 | 3198.659 |
| `json_parse` | **9.061** | 9.283 | 12.185 | 40.113 | 41.468 |
| `nbody` | 41.246 | 41.181 | **39.130** | 103.555 | 3143.593 |

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
| _(floor: empty program)_ | _2.837_ | _75.933_ | _**78.770**_ | _55.106_ | _59.932_ |
| `lcg` | 3.044 | 81.610 | **84.654** | 64.510 | 67.532 |
| `packet_classifier` | 3.264 | 88.585 | **91.849** | 68.132 | 68.540 |
| `ring_write` | 3.497 | 87.520 | **91.017** | 69.162 | 70.240 |
| `histogram_bins` | 3.495 | 87.781 | **91.276** | 69.419 | 71.568 |
| `prefix_scan` | 3.667 | 89.129 | **92.796** | 70.879 | 70.933 |
| `binary_search` | 3.869 | 87.468 | **91.337** | 67.562 | 74.788 |
| `sort_window` | 3.982 | 96.877 | **100.859** | 75.722 | 81.835 |
| `bloom_filter` | 4.128 | 91.948 | **96.076** | 75.301 | 75.594 |
| `hash_join` | 8.945 | 210.208 | **219.153** | 119.329 | 112.749 |
| `sieve` | 3.570 | 88.574 | **92.144** | 76.828 | 79.032 |
| `fib` | 3.036 | 81.398 | **84.434** | 65.640 | 67.240 |
| `collatz` | 3.417 | 85.940 | **89.357** | 66.850 | 70.224 |
| `matmul` | 4.562 | 96.560 | **101.122** | 79.790 | 93.733 |
| `json_parse` | 73.669 | 757.734 | **831.403** | 131.909 | 193.454 |
| `nbody` | 7.737 | 116.545 | **124.282** | 103.183 | 102.033 |

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
