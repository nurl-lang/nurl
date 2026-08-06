# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-06T08:24:07Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `83f5658bb919b0779f372d8069aa0733bbc628ca` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31084422385 |
| NURL | `v0.33.0-65-g83f5658b` |
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
| _(floor: empty program)_ | _1.676_ | _1.725_ | _1.927_ | _22.470_ | _17.132_ |
| `lcg` | **39.318** | 39.405 | 39.442 | 1878.070 | 5172.184 |
| `packet_classifier` | **56.369** | 56.471 | 56.575 | 161.726 | 4383.208 |
| `ring_write` | **42.385** | 42.412 | 42.549 | 66.504 | 6154.507 |
| `histogram_bins` | **39.655** | 41.354 | 39.918 | 64.960 | 6169.577 |
| `prefix_scan` | **21.844** | 21.987 | 22.040 | 64.598 | 4429.325 |
| `binary_search` | 39.846 | **38.605** | 43.329 | 105.229 | 6302.189 |
| `sort_window` | 27.451 | 27.478 | **26.976** | 196.953 | 13941.287 |
| `bloom_filter` | **18.011** | 18.257 | 18.516 | 2815.151 | 7490.739 |
| `hash_join` | **28.218** | 30.105 | 30.042 | 3417.591 | 8151.308 |
| `sieve` | 20.170 | 19.844 | **18.111** | 66.821 | 3375.728 |
| `fib` | **25.312** | 30.088 | 28.246 | 130.099 | 1367.324 |
| `collatz` | **12.445** | 12.460 | 12.549 | 48.740 | 711.672 |
| `matmul` | **33.505** | 33.595 | 33.738 | 75.561 | 3238.840 |
| `json_parse` | **8.759** | 8.807 | 11.734 | 34.713 | 37.589 |
| `nbody` | 40.858 | 40.876 | **39.113** | 99.928 | 3022.185 |

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
| _(floor: empty program)_ | _2.641_ | _79.683_ | _**82.324**_ | _55.243_ | _60.712_ |
| `lcg` | 2.796 | 83.933 | **86.729** | 64.411 | 68.106 |
| `packet_classifier` | 2.843 | 85.205 | **88.048** | 66.482 | 68.169 |
| `ring_write` | 2.888 | 86.458 | **89.346** | 66.659 | 68.800 |
| `histogram_bins` | 2.930 | 88.613 | **91.543** | 68.819 | 70.869 |
| `prefix_scan` | 2.973 | 90.604 | **93.577** | 71.091 | 69.924 |
| `binary_search` | 3.112 | 89.140 | **92.252** | 66.934 | 73.410 |
| `sort_window` | 3.111 | 94.854 | **97.965** | 73.541 | 78.865 |
| `bloom_filter` | 3.289 | 94.886 | **98.175** | 74.838 | 73.137 |
| `hash_join` | 5.318 | 207.450 | **212.768** | 116.678 | 109.339 |
| `sieve` | 2.978 | 91.396 | **94.374** | 76.819 | 77.083 |
| `fib` | 2.749 | 82.517 | **85.266** | 65.011 | 64.909 |
| `collatz` | 2.896 | 88.153 | **91.049** | 66.565 | 68.888 |
| `matmul` | 3.266 | 95.257 | **98.523** | 78.977 | 90.948 |
| `json_parse` | 39.597 | 508.186 | **547.783** | 120.497 | 174.787 |
| `nbody` | 4.313 | 105.766 | **110.079** | 94.619 | 91.181 |

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
