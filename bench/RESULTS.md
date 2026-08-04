# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T18:24:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `6d12d3843d8c159758ecde7bce87e11b3d19cb87` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30938119740 |
| NURL | `v0.32.0-44-g6d12d384` |
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
| _(floor: empty program)_ | _1.812_ | _1.899_ | _2.049_ | _25.873_ | _18.139_ |
| `lcg` | 44.525 | **44.494** | 44.551 | 1834.859 | 5422.652 |
| `packet_classifier` | **63.678** | 63.924 | 64.009 | 160.051 | 4598.062 |
| `ring_write` | **47.849** | 47.907 | 48.078 | 73.932 | 6825.459 |
| `histogram_bins` | **44.748** | 44.916 | 45.081 | 76.355 | 6215.412 |
| `prefix_scan` | **24.768** | 24.772 | 25.021 | 73.467 | 4597.360 |
| `binary_search` | **36.000** | 36.131 | 46.313 | 113.377 | 6671.338 |
| `sort_window` | 31.006 | 31.069 | **30.454** | 165.784 | 10987.473 |
| `bloom_filter` | **19.928** | 20.644 | 20.972 | 2799.360 | 7694.279 |
| `hash_join` | **29.476** | 31.009 | 31.521 | 3415.218 | 8208.267 |
| `sieve` | 20.670 | 20.577 | **20.391** | 75.562 | 3538.209 |
| `fib` | **28.176** | 33.653 | 29.639 | 142.891 | 1291.925 |
| `collatz` | **13.942** | 13.954 | 14.031 | 52.584 | 754.567 |
| `matmul` | **45.603** | 46.478 | 46.036 | 84.894 | 3342.401 |
| `json_parse` | **8.588** | 9.114 | 12.528 | 40.185 | 38.302 |
| `nbody` | 46.326 | 46.459 | **44.224** | 96.299 | 3254.963 |

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
| _(floor: empty program)_ | _2.950_ | _91.953_ | _**94.903**_ | _68.177_ | _66.660_ |
| `lcg` | 3.056 | 97.439 | **100.495** | 74.525 | 76.395 |
| `packet_classifier` | 3.179 | 100.519 | **103.698** | 75.673 | 76.406 |
| `ring_write` | 3.248 | 98.414 | **101.662** | 75.327 | 75.934 |
| `histogram_bins` | 3.282 | 101.576 | **104.858** | 77.955 | 77.454 |
| `prefix_scan` | 3.350 | 107.403 | **110.753** | 82.379 | 81.056 |
| `binary_search` | 3.605 | 106.248 | **109.853** | 79.577 | 83.955 |
| `sort_window` | 3.494 | 110.910 | **114.404** | 84.552 | 87.105 |
| `bloom_filter` | 3.734 | 109.987 | **113.721** | 85.860 | 83.134 |
| `hash_join` | 5.772 | 216.440 | **222.212** | 126.349 | 117.767 |
| `sieve` | 3.320 | 101.850 | **105.170** | 85.573 | 86.363 |
| `fib` | 3.056 | 93.333 | **96.389** | 73.754 | 71.413 |
| `collatz` | 3.220 | 99.424 | **102.644** | 75.941 | 75.770 |
| `matmul` | 3.576 | 104.876 | **108.452** | 85.546 | 99.112 |
| `json_parse` | 39.623 | 497.380 | **537.003** | 126.944 | 186.685 |
| `nbody` | 4.580 | 116.553 | **121.133** | 101.199 | 98.905 |

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
