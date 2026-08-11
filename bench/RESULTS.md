# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T11:55:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `830a725683b9f9c66dd46bc64b72441dfd66ae7a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31488460904 |
| NURL | `v0.37.1-4-g830a7256` |
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
| _(floor: empty program)_ | _1.411_ | _1.360_ | _1.386_ | _19.220_ | _14.008_ |
| `lcg` | **35.226** | 40.305 | 37.388 | 1339.278 | 3907.963 |
| `packet_classifier` | **58.314** | 61.978 | 60.385 | 150.492 | 3285.681 |
| `ring_write` | **38.914** | 39.029 | 39.360 | 58.447 | 4645.184 |
| `histogram_bins` | 39.091 | **36.306** | 37.258 | 60.929 | 4500.668 |
| `prefix_scan` | **19.449** | 19.879 | 20.388 | 58.449 | 3340.380 |
| `binary_search` | 29.996 | **28.071** | 38.672 | 96.445 | 4876.549 |
| `sort_window` | **36.015** | 45.486 | 36.583 | 158.302 | 8478.392 |
| `bloom_filter` | 12.627 | **12.494** | 12.740 | 2139.593 | 5902.774 |
| `hash_join` | **22.036** | 23.110 | 23.860 | 2683.658 | 6335.837 |
| `sieve` | **31.996** | 32.614 | 32.138 | 72.987 | 2337.070 |
| `fib` | 26.510 | 27.398 | **23.780** | 97.863 | 801.891 |
| `collatz` | **13.409** | 13.560 | 14.441 | 53.124 | 507.982 |
| `matmul` | 19.096 | 18.451 | **17.850** | 66.827 | 2242.802 |
| `json_parse` | **6.820** | 7.061 | 8.635 | 29.617 | 30.602 |
| `nbody` | 28.438 | 28.504 | **26.399** | 72.354 | 1996.934 |

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
| _(floor: empty program)_ | _2.308_ | _64.993_ | _**67.301**_ | _41.234_ | _54.692_ |
| `lcg` | 2.349 | 67.851 | **70.200** | 48.275 | 56.901 |
| `packet_classifier` | 2.259 | 66.598 | **68.857** | 51.724 | 59.376 |
| `ring_write` | 2.564 | 69.829 | **72.393** | 116.050 | 62.624 |
| `histogram_bins` | 2.464 | 69.352 | **71.816** | 47.870 | 61.649 |
| `prefix_scan` | 2.450 | 71.839 | **74.289** | 53.909 | 60.052 |
| `binary_search` | 2.592 | 79.766 | **82.358** | 49.539 | 59.813 |
| `sort_window` | 2.607 | 75.369 | **77.976** | 57.564 | 66.874 |
| `bloom_filter` | 2.869 | 78.600 | **81.469** | 56.274 | 64.925 |
| `hash_join` | 4.558 | 157.760 | **162.318** | 92.005 | 94.837 |
| `sieve` | 2.479 | 77.127 | **79.606** | 59.909 | 67.441 |
| `fib` | 2.252 | 63.554 | **65.806** | 48.982 | 54.927 |
| `collatz` | 2.364 | 66.915 | **69.279** | 49.000 | 58.306 |
| `matmul` | 2.592 | 71.944 | **74.536** | 59.768 | 79.554 |
| `json_parse` | 36.533 | 425.239 | **461.772** | 97.988 | 166.467 |
| `nbody` | 3.683 | 87.746 | **91.429** | 73.556 | 79.943 |

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
