# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T18:23:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `884d2ce5c10d9e553fe08c78c60cf4a90d84d9fd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30569813764 |
| NURL | `v0.29.0-56-g884d2ce` |
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
| _(floor: empty program)_ | _1.800_ | _1.861_ | _2.036_ | _25.237_ | _18.261_ |
| `lcg` | **44.426** | 44.479 | 44.574 | 1833.175 | 5338.773 |
| `packet_classifier` | 63.955 | **63.917** | 64.052 | 159.501 | 4593.437 |
| `ring_write` | **47.905** | 47.985 | 48.085 | 74.492 | 6815.001 |
| `histogram_bins` | **44.935** | 44.969 | 45.070 | 75.509 | 6546.150 |
| `prefix_scan` | **24.641** | 24.778 | 24.912 | 73.459 | 4696.250 |
| `binary_search` | **35.827** | 36.267 | 46.501 | 111.053 | 7395.718 |
| `sort_window` | 31.065 | 30.999 | **30.380** | 166.779 | 10971.279 |
| `bloom_filter` | **19.902** | 20.565 | 20.948 | 2808.022 | 7737.656 |
| `hash_join` | **29.403** | 31.023 | 31.388 | 3416.614 | 8212.928 |
| `sieve` | 20.630 | **20.572** | 20.738 | 73.406 | 3555.819 |
| `fib` | **28.099** | 33.502 | 29.500 | 143.253 | 1290.899 |
| `collatz` | **13.996** | 14.001 | 14.005 | 52.541 | 753.991 |
| `matmul` | 45.674 | **45.602** | 46.782 | 84.022 | 3463.110 |
| `json_parse` | **8.317** | 9.110 | 12.394 | 38.713 | 38.017 |
| `nbody` | 46.335 | 46.421 | **44.185** | 98.343 | 3290.114 |

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
| _(floor: empty program)_ | _3.353_ | _92.303_ | _**95.656**_ | _68.483_ | _68.066_ |
| `lcg` | 3.602 | 96.813 | **100.415** | 75.686 | 76.168 |
| `packet_classifier` | 3.765 | 99.345 | **103.110** | 78.426 | 76.398 |
| `ring_write` | 4.006 | 100.580 | **104.586** | 79.014 | 76.652 |
| `histogram_bins` | 4.078 | 104.552 | **108.630** | 80.977 | 80.998 |
| `prefix_scan` | 4.227 | 105.535 | **109.762** | 82.789 | 80.646 |
| `binary_search` | 4.470 | 103.442 | **107.912** | 80.706 | 84.476 |
| `sort_window` | 4.613 | 110.147 | **114.760** | 85.437 | 87.497 |
| `bloom_filter` | 4.830 | 106.482 | **111.312** | 86.402 | 84.329 |
| `hash_join` | 9.696 | 214.491 | **224.187** | 125.005 | 122.484 |
| `sieve` | 4.199 | 104.326 | **108.525** | 85.906 | 87.259 |
| `fib` | 3.571 | 95.113 | **98.684** | 74.440 | 76.192 |
| `collatz` | 3.919 | 101.550 | **105.469** | 77.548 | 77.055 |
| `matmul` | 4.904 | 107.855 | **112.759** | 89.263 | 101.451 |
| `json_parse` | 78.738 | 704.135 | **782.873** | 127.206 | 192.093 |
| `nbody` | 7.332 | 118.495 | **125.827** | 101.564 | 101.792 |

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
