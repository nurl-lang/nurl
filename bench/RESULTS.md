# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T13:59:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0671003276c00729b2b9ab74d8fbe019a03cbab0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31184933737 |
| NURL | `v0.35.0-3-g06710032` |
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
| _(floor: empty program)_ | _1.671_ | _1.738_ | _1.927_ | _24.055_ | _17.730_ |
| `lcg` | 39.666 | **39.582** | 39.842 | 1887.485 | 5175.296 |
| `packet_classifier` | **56.793** | 56.795 | 56.991 | 164.510 | 4559.739 |
| `ring_write` | **42.700** | 42.761 | 42.874 | 68.427 | 6366.541 |
| `histogram_bins` | **40.109** | 41.821 | 40.353 | 68.234 | 6382.271 |
| `prefix_scan` | **22.068** | 22.349 | 22.614 | 68.007 | 4579.776 |
| `binary_search` | 39.960 | **38.787** | 43.773 | 107.363 | 6421.280 |
| `sort_window` | 27.617 | 27.696 | **27.077** | 198.177 | 11495.508 |
| `bloom_filter` | **18.300** | 18.407 | 18.778 | 2875.982 | 7420.916 |
| `hash_join` | **28.200** | 30.388 | 30.136 | 3519.588 | 8538.069 |
| `sieve` | 21.195 | 20.749 | **20.362** | 66.889 | 3203.814 |
| `fib` | **25.348** | 30.143 | 28.590 | 134.428 | 1364.135 |
| `collatz` | 12.488 | **12.414** | 12.587 | 50.744 | 713.464 |
| `matmul` | **33.902** | 33.951 | 34.017 | 76.898 | 3553.683 |
| `json_parse` | **8.782** | 9.020 | 11.860 | 35.925 | 37.225 |
| `nbody` | 41.037 | 40.924 | **39.138** | 101.397 | 3032.545 |

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
| _(floor: empty program)_ | _2.916_ | _84.376_ | _**87.292**_ | _59.563_ | _60.876_ |
| `lcg` | 2.900 | 87.727 | **90.627** | 68.046 | 70.782 |
| `packet_classifier` | 3.142 | 96.286 | **99.428** | 71.991 | 71.727 |
| `ring_write` | 3.070 | 95.375 | **98.445** | 72.978 | 75.293 |
| `histogram_bins` | 3.018 | 97.901 | **100.919** | 75.001 | 72.926 |
| `prefix_scan` | 3.051 | 94.353 | **97.404** | 73.961 | 72.418 |
| `binary_search` | 3.179 | 96.102 | **99.281** | 71.687 | 77.494 |
| `sort_window` | 3.255 | 104.286 | **107.541** | 79.256 | 81.258 |
| `bloom_filter` | 3.453 | 100.955 | **104.408** | 78.987 | 94.723 |
| `hash_join` | 5.325 | 215.362 | **220.687** | 120.360 | 112.103 |
| `sieve` | 2.985 | 94.274 | **97.259** | 79.225 | 79.154 |
| `fib` | 2.806 | 89.220 | **92.026** | 67.292 | 68.622 |
| `collatz` | 3.017 | 91.817 | **94.834** | 68.570 | 70.095 |
| `matmul` | 3.211 | 96.767 | **99.978** | 80.800 | 94.137 |
| `json_parse` | 39.574 | 517.735 | **557.309** | 123.975 | 180.853 |
| `nbody` | 4.286 | 107.586 | **111.872** | 95.800 | 92.759 |

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
