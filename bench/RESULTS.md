# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T15:56:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ef5ea5263b394a2def2a9067ef48345a5593af5c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31265536547 |
| NURL | `v0.35.1-47-gef5ea526` |
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
| _(floor: empty program)_ | _1.827_ | _1.869_ | _2.037_ | _23.886_ | _18.095_ |
| `lcg` | **44.249** | 44.318 | 44.519 | 1830.246 | 5502.994 |
| `packet_classifier` | 63.747 | **63.702** | 63.956 | 158.634 | 4601.533 |
| `ring_write` | **47.797** | 47.860 | 47.947 | 74.909 | 6995.740 |
| `histogram_bins` | **44.795** | 44.821 | 45.006 | 74.747 | 6444.074 |
| `prefix_scan` | **24.664** | 24.730 | 24.893 | 71.384 | 4635.662 |
| `binary_search` | **35.917** | 36.077 | 46.163 | 110.956 | 6397.682 |
| `sort_window` | 31.015 | 30.936 | **30.328** | 166.954 | 12232.332 |
| `bloom_filter` | **19.981** | 20.562 | 20.872 | 2777.771 | 8046.809 |
| `hash_join` | **29.325** | 30.936 | 31.365 | 3463.827 | 8252.788 |
| `sieve` | 20.776 | 20.507 | **20.317** | 71.442 | 3350.584 |
| `fib` | **28.110** | 33.469 | 29.507 | 143.243 | 1304.749 |
| `collatz` | **13.821** | 13.956 | 13.991 | 51.357 | 752.397 |
| `matmul` | **45.617** | 45.922 | 45.958 | 84.296 | 3392.005 |
| `json_parse` | 45.688 | **9.149** | 12.550 | 38.321 | 38.509 |
| `nbody` | 46.246 | 46.411 | **44.213** | 97.799 | 3312.689 |

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
| _(floor: empty program)_ | _2.977_ | _87.662_ | _**90.639**_ | _63.865_ | _70.722_ |
| `lcg` | 3.076 | 94.325 | **97.401** | 72.191 | 74.947 |
| `packet_classifier` | 3.239 | 96.992 | **100.231** | 74.390 | 74.332 |
| `ring_write` | 3.286 | 96.626 | **99.912** | 75.378 | 75.401 |
| `histogram_bins` | 3.337 | 98.831 | **102.168** | 77.881 | 77.381 |
| `prefix_scan` | 3.429 | 101.124 | **104.553** | 78.019 | 78.081 |
| `binary_search` | 3.464 | 100.460 | **103.924** | 75.747 | 80.650 |
| `sort_window` | 3.618 | 106.961 | **110.579** | 81.808 | 84.472 |
| `bloom_filter` | 3.781 | 104.129 | **107.910** | 82.230 | 81.491 |
| `hash_join` | 5.838 | 210.201 | **216.039** | 121.704 | 116.216 |
| `sieve` | 3.404 | 100.533 | **103.937** | 84.364 | 85.294 |
| `fib` | 3.098 | 92.399 | **95.497** | 73.519 | 73.582 |
| `collatz` | 3.292 | 98.297 | **101.589** | 73.350 | 76.412 |
| `matmul` | 3.593 | 104.725 | **108.318** | 85.607 | 98.620 |
| `json_parse` | 40.493 | 519.864 | **560.357** | 125.943 | 187.225 |
| `nbody` | 4.663 | 115.740 | **120.403** | 100.146 | 99.490 |

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
