# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-12T17:51:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `3dc57da1ad01dc381ec568fc10b6dbcbfe4cece3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31624340141 |
| NURL | `v0.39.0-15-g3dc57da1` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
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
| _(floor: empty program)_ | _1.658_ | _1.699_ | _1.852_ | _23.523_ | _17.746_ |
| `lcg` | **39.322** | 39.491 | 39.573 | 2050.229 | 5109.756 |
| `packet_classifier` | 56.787 | **56.716** | 56.844 | 163.674 | 4481.765 |
| `ring_write` | 42.638 | **42.523** | 42.976 | 67.348 | 6134.917 |
| `histogram_bins` | **39.904** | 41.604 | 40.116 | 66.837 | 5859.660 |
| `prefix_scan` | 21.943 | **21.935** | 22.253 | 65.384 | 4769.595 |
| `binary_search` | 39.988 | **38.578** | 43.734 | 108.447 | 6065.719 |
| `sort_window` | 27.447 | 27.545 | **27.087** | 197.015 | 11304.133 |
| `bloom_filter` | **18.073** | 18.335 | 18.562 | 2829.932 | 7905.861 |
| `hash_join` | **28.412** | 30.538 | 30.343 | 3424.642 | 8259.671 |
| `sieve` | 19.895 | 18.981 | **18.928** | 68.867 | 3307.635 |
| `fib` | **25.555** | 30.491 | 28.661 | 133.534 | 1370.111 |
| `collatz` | **12.488** | 12.547 | 12.621 | 50.270 | 717.198 |
| `matmul` | 34.069 | **33.960** | 34.294 | 77.972 | 3096.030 |
| `json_parse` | 9.164 | **8.938** | 11.952 | 37.434 | 38.851 |
| `nbody` | 41.089 | 41.123 | **39.411** | 101.444 | 3125.881 |

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
| _(floor: empty program)_ | _2.742_ | _82.446_ | _**85.188**_ | _58.504_ | _61.031_ |
| `lcg` | 2.893 | 88.240 | **91.133** | 68.290 | 68.948 |
| `packet_classifier` | 3.086 | 90.688 | **93.774** | 69.061 | 69.767 |
| `ring_write` | 3.081 | 92.738 | **95.819** | 70.679 | 70.391 |
| `histogram_bins` | 3.292 | 96.925 | **100.217** | 73.857 | 75.109 |
| `prefix_scan` | 3.132 | 98.697 | **101.829** | 75.020 | 73.182 |
| `binary_search` | 3.230 | 93.697 | **96.927** | 72.242 | 76.399 |
| `sort_window` | 3.439 | 103.377 | **106.816** | 79.498 | 80.249 |
| `bloom_filter` | 3.603 | 101.858 | **105.461** | 79.699 | 78.771 |
| `hash_join` | 5.747 | 217.518 | **223.265** | 124.372 | 114.748 |
| `sieve` | 3.209 | 97.593 | **100.802** | 83.066 | 82.247 |
| `fib` | 3.082 | 92.159 | **95.241** | 71.538 | 76.326 |
| `collatz` | 3.114 | 94.366 | **97.480** | 71.311 | 72.763 |
| `matmul` | 3.418 | 100.842 | **104.260** | 84.654 | 96.110 |
| `json_parse` | 46.667 | 545.396 | **592.063** | 126.357 | 181.731 |
| `nbody` | 4.607 | 117.261 | **121.868** | 98.185 | 96.193 |

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
