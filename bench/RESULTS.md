# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T06:22:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `1669f532a18177bf2ffd467657c32c058347ed50` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30687458714 |
| NURL | `v0.30.0-5-g1669f53` |
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
| _(floor: empty program)_ | _1.677_ | _1.733_ | _1.873_ | _22.725_ | _17.207_ |
| `lcg` | 39.290 | **39.260** | 39.466 | 1872.577 | 5369.478 |
| `packet_classifier` | 56.466 | **56.442** | 56.562 | 161.971 | 4344.161 |
| `ring_write` | **42.259** | 42.470 | 42.554 | 64.876 | 6196.764 |
| `histogram_bins` | **39.727** | 41.442 | 39.997 | 67.403 | 6148.184 |
| `prefix_scan` | **21.906** | 21.907 | 22.044 | 65.600 | 4655.522 |
| `binary_search` | 39.960 | **38.346** | 43.433 | 105.623 | 5857.228 |
| `sort_window` | 27.332 | 27.437 | **26.878** | 199.250 | 11343.199 |
| `bloom_filter` | **18.032** | 18.269 | 18.550 | 2857.508 | 7690.992 |
| `hash_join` | **28.275** | 30.221 | 29.959 | 3393.534 | 8183.357 |
| `sieve` | 20.221 | **19.965** | 20.422 | 65.576 | 3321.136 |
| `fib` | **25.366** | 29.944 | 28.364 | 131.736 | 1345.402 |
| `collatz` | 12.442 | **12.418** | 12.580 | 48.854 | 715.693 |
| `matmul` | 35.291 | 34.287 | **33.651** | 74.617 | 3054.454 |
| `json_parse` | **8.591** | 8.855 | 11.715 | 35.399 | 37.192 |
| `nbody` | 41.014 | 41.053 | **39.052** | 98.032 | 3067.510 |

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
| _(floor: empty program)_ | _2.658_ | _78.987_ | _**81.645**_ | _57.987_ | _61.496_ |
| `lcg` | 2.809 | 82.193 | **85.002** | 65.282 | 68.230 |
| `packet_classifier` | 2.842 | 85.007 | **87.849** | 66.776 | 67.503 |
| `ring_write` | 3.006 | 84.013 | **87.019** | 67.329 | 69.932 |
| `histogram_bins` | 3.076 | 88.656 | **91.732** | 70.305 | 69.837 |
| `prefix_scan` | 3.110 | 91.513 | **94.623** | 73.324 | 70.546 |
| `binary_search` | 3.343 | 87.950 | **91.293** | 67.562 | 73.119 |
| `sort_window` | 3.319 | 96.588 | **99.907** | 75.274 | 78.726 |
| `bloom_filter` | 3.612 | 93.939 | **97.551** | 75.001 | 82.055 |
| `hash_join` | 6.921 | 209.623 | **216.544** | 117.281 | 118.127 |
| `sieve` | 3.149 | 89.415 | **92.564** | 76.689 | 77.564 |
| `fib` | 2.799 | 81.579 | **84.378** | 64.759 | 66.152 |
| `collatz` | 2.989 | 86.306 | **89.295** | 67.472 | 69.672 |
| `matmul` | 3.526 | 93.554 | **97.080** | 78.698 | 90.349 |
| `json_parse` | 54.238 | 511.641 | **565.879** | 123.388 | 176.552 |
| `nbody` | 4.944 | 105.091 | **110.035** | 95.341 | 92.442 |

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
