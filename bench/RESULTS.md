# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T20:16:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `179e1fa62736bf7eb35c9b68f624415e2a59b0e7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30716432139 |
| NURL | `v0.30.0-31-g179e1fa` |
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
| _(floor: empty program)_ | _1.731_ | _1.758_ | _1.966_ | _24.466_ | _18.372_ |
| `lcg` | **39.579** | 39.614 | 39.890 | 1883.501 | 5175.966 |
| `packet_classifier` | **56.824** | 56.831 | 56.836 | 164.566 | 4415.941 |
| `ring_write` | **42.603** | 42.698 | 42.917 | 68.547 | 6366.325 |
| `histogram_bins` | **40.017** | 41.603 | 40.084 | 68.283 | 5932.151 |
| `prefix_scan` | 22.267 | **22.261** | 22.394 | 67.191 | 4659.362 |
| `binary_search` | 40.187 | **38.597** | 43.713 | 108.853 | 6193.779 |
| `sort_window` | 27.721 | 27.701 | **27.112** | 199.337 | 11256.794 |
| `bloom_filter` | **18.324** | 18.603 | 18.724 | 2842.116 | 7665.121 |
| `hash_join` | **28.220** | 30.553 | 30.307 | 3441.253 | 8147.280 |
| `sieve` | 19.238 | **18.643** | 18.807 | 68.277 | 3342.974 |
| `fib` | **25.571** | 30.463 | 28.675 | 132.496 | 1351.231 |
| `collatz` | 12.736 | **12.579** | 12.831 | 51.990 | 719.398 |
| `matmul` | 34.066 | **33.955** | 34.203 | 78.224 | 3123.269 |
| `json_parse` | **8.819** | 9.102 | 12.010 | 37.886 | 39.943 |
| `nbody` | 41.352 | 41.403 | **39.539** | 104.898 | 3123.234 |

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
| _(floor: empty program)_ | _3.440_ | _84.224_ | _**87.664**_ | _62.640_ | _64.526_ |
| `lcg` | 2.988 | 93.102 | **96.090** | 72.118 | 76.243 |
| `packet_classifier` | 3.022 | 93.355 | **96.377** | 72.641 | 72.492 |
| `ring_write` | 2.976 | 95.382 | **98.358** | 74.213 | 74.307 |
| `histogram_bins` | 3.196 | 97.371 | **100.567** | 75.653 | 76.572 |
| `prefix_scan` | 3.306 | 99.367 | **102.673** | 77.071 | 75.336 |
| `binary_search` | 3.308 | 95.625 | **98.933** | 74.279 | 79.141 |
| `sort_window` | 3.339 | 105.633 | **108.972** | 81.862 | 84.056 |
| `bloom_filter` | 3.570 | 104.532 | **108.102** | 81.191 | 84.495 |
| `hash_join` | 5.629 | 217.099 | **222.728** | 125.884 | 115.880 |
| `sieve` | 3.133 | 98.994 | **102.127** | 83.089 | 84.017 |
| `fib` | 2.914 | 89.553 | **92.467** | 70.989 | 75.627 |
| `collatz` | 3.014 | 94.476 | **97.490** | 70.896 | 73.832 |
| `matmul` | 3.373 | 103.282 | **106.655** | 86.326 | 103.470 |
| `json_parse` | 40.254 | 534.260 | **574.514** | 127.114 | 185.003 |
| `nbody` | 4.493 | 113.892 | **118.385** | 100.993 | 98.634 |

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
