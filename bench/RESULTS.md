# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T15:48:07Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0130d5672dfbd108911a45487ec8d4d37939f029` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31508579562 |
| NURL | `v0.37.1-10-g0130d567` |
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
| _(floor: empty program)_ | _1.688_ | _1.728_ | _1.877_ | _23.397_ | _18.111_ |
| `lcg` | 39.559 | **39.463** | 39.566 | 1880.418 | 5080.298 |
| `packet_classifier` | **56.673** | 56.738 | 56.944 | 163.043 | 4397.240 |
| `ring_write` | **42.630** | 42.665 | 42.796 | 67.109 | 6426.808 |
| `histogram_bins` | **39.861** | 41.551 | 40.169 | 67.778 | 5956.989 |
| `prefix_scan` | 22.187 | **22.097** | 22.308 | 66.099 | 4541.942 |
| `binary_search` | 40.298 | **38.697** | 43.622 | 107.946 | 5953.803 |
| `sort_window` | 27.576 | 27.712 | **27.284** | 197.480 | 11329.835 |
| `bloom_filter` | **18.145** | 18.401 | 18.762 | 2832.169 | 7820.914 |
| `hash_join` | **28.337** | 30.541 | 30.270 | 3417.247 | 8173.328 |
| `sieve` | 19.149 | 20.867 | **18.989** | 67.737 | 3308.039 |
| `fib` | **25.478** | 30.230 | 28.573 | 132.018 | 1353.498 |
| `collatz` | **12.515** | 12.539 | 12.608 | 51.209 | 709.004 |
| `matmul` | **33.753** | 34.311 | 34.048 | 76.774 | 4018.815 |
| `json_parse` | 8.886 | **8.862** | 11.742 | 36.675 | 38.118 |
| `nbody` | 40.978 | 41.076 | **39.291** | 103.072 | 3029.073 |

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
| _(floor: empty program)_ | _2.817_ | _83.698_ | _**86.515**_ | _61.727_ | _68.102_ |
| `lcg` | 2.926 | 90.945 | **93.871** | 69.718 | 70.474 |
| `packet_classifier` | 2.885 | 91.804 | **94.689** | 70.842 | 69.444 |
| `ring_write` | 3.005 | 95.041 | **98.046** | 72.538 | 71.992 |
| `histogram_bins` | 3.085 | 95.236 | **98.321** | 72.668 | 73.613 |
| `prefix_scan` | 3.106 | 96.059 | **99.165** | 74.834 | 73.607 |
| `binary_search` | 3.222 | 95.513 | **98.735** | 71.621 | 76.359 |
| `sort_window` | 3.256 | 102.124 | **105.380** | 78.615 | 81.173 |
| `bloom_filter` | 3.495 | 102.306 | **105.801** | 80.318 | 76.567 |
| `hash_join` | 5.616 | 216.138 | **221.754** | 123.771 | 113.757 |
| `sieve` | 3.093 | 95.306 | **98.399** | 81.271 | 80.586 |
| `fib` | 2.864 | 87.706 | **90.570** | 68.701 | 68.395 |
| `collatz` | 3.067 | 93.852 | **96.919** | 70.349 | 70.878 |
| `matmul` | 3.321 | 99.316 | **102.637** | 81.972 | 92.148 |
| `json_parse` | 43.388 | 543.536 | **586.924** | 126.308 | 180.328 |
| `nbody` | 4.546 | 109.697 | **114.243** | 98.961 | 94.485 |

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
