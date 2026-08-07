# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T09:40:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1021-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `30ae6907e0a625a44756833ae626b5f18aa393c7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31166631157 |
| NURL | `v0.34.0-26-g30ae6907` |
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
| _(floor: empty program)_ | _1.240_ | _1.303_ | _1.358_ | _20.769_ | _13.770_ |
| `lcg` | **35.019** | 35.208 | 35.349 | 1376.237 | 4024.769 |
| `packet_classifier` | **56.711** | 61.838 | 59.693 | 146.501 | 3111.923 |
| `ring_write` | **38.867** | 39.433 | 39.668 | 57.696 | 4737.239 |
| `histogram_bins` | **35.925** | 36.148 | 36.145 | 59.859 | 4990.696 |
| `prefix_scan` | **19.666** | 19.728 | 19.920 | 56.195 | 3247.983 |
| `binary_search` | 29.765 | **27.571** | 39.369 | 96.858 | 4892.732 |
| `sort_window` | 36.082 | 45.105 | **35.284** | 157.030 | 7988.827 |
| `bloom_filter` | **12.410** | 12.533 | 12.746 | 2112.778 | 5740.625 |
| `hash_join` | **21.532** | 23.534 | 23.510 | 2675.859 | 6119.593 |
| `sieve` | 32.292 | **32.153** | 32.165 | 72.508 | 2377.059 |
| `fib` | 24.831 | 26.254 | **22.686** | 96.825 | 779.094 |
| `collatz` | **13.156** | 13.446 | 14.018 | 53.110 | 491.260 |
| `matmul` | **17.595** | 17.844 | 18.539 | 64.015 | 2207.257 |
| `json_parse` | **6.580** | 6.594 | 8.352 | 26.913 | 28.255 |
| `nbody` | 28.400 | 28.348 | **26.057** | 69.256 | 1914.020 |

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
| _(floor: empty program)_ | _2.059_ | _56.540_ | _**58.599**_ | _39.525_ | _49.504_ |
| `lcg` | 2.119 | 59.271 | **61.390** | 43.515 | 55.566 |
| `packet_classifier` | 2.195 | 61.192 | **63.387** | 45.388 | 56.062 |
| `ring_write` | 2.267 | 65.266 | **67.533** | 48.908 | 57.865 |
| `histogram_bins` | 2.386 | 66.785 | **69.171** | 46.126 | 58.138 |
| `prefix_scan` | 2.406 | 69.654 | **72.060** | 51.799 | 58.835 |
| `binary_search` | 2.494 | 68.958 | **71.452** | 51.211 | 62.956 |
| `sort_window` | 2.433 | 69.594 | **72.027** | 51.330 | 63.442 |
| `bloom_filter` | 2.674 | 72.681 | **75.355** | 53.714 | 61.101 |
| `hash_join` | 4.355 | 150.085 | **154.440** | 85.225 | 90.304 |
| `sieve` | 2.321 | 68.076 | **70.397** | 52.399 | 65.215 |
| `fib` | 2.134 | 60.146 | **62.280** | 43.928 | 53.918 |
| `collatz` | 2.523 | 70.274 | **72.797** | 52.155 | 60.972 |
| `matmul` | 2.605 | 72.826 | **75.431** | 55.139 | 75.234 |
| `json_parse` | 34.333 | 391.927 | **426.260** | 87.802 | 156.033 |
| `nbody` | 3.276 | 82.121 | **85.397** | 74.977 | 79.639 |

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
