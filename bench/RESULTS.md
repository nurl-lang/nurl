# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-03T05:43:30Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c897087746ac479b834fe3a68291b10044077538` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30787757677 |
| NURL | `v0.31.1-4-gc8970877` |
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
| _(floor: empty program)_ | _1.676_ | _1.703_ | _1.876_ | _22.609_ | _17.043_ |
| `lcg` | **39.342** | 39.364 | 39.408 | 1883.372 | 5126.614 |
| `packet_classifier` | 56.631 | **56.444** | 56.633 | 163.378 | 4366.970 |
| `ring_write` | **42.290** | 42.450 | 42.570 | 65.583 | 6175.036 |
| `histogram_bins` | **39.734** | 41.362 | 39.916 | 67.373 | 5917.444 |
| `prefix_scan` | 21.906 | **21.875** | 22.007 | 64.600 | 4477.220 |
| `binary_search` | 39.888 | **38.561** | 43.259 | 105.585 | 6157.033 |
| `sort_window` | 27.410 | 27.462 | **26.934** | 196.791 | 11375.364 |
| `bloom_filter` | **18.061** | 18.201 | 18.514 | 2809.971 | 9334.711 |
| `hash_join` | **28.177** | 30.232 | 30.037 | 3398.419 | 8458.758 |
| `sieve` | 18.330 | 18.351 | **18.178** | 66.598 | 3418.833 |
| `fib` | **25.292** | 30.110 | 28.321 | 131.826 | 1374.952 |
| `collatz` | **12.481** | 12.504 | 12.599 | 48.279 | 715.954 |
| `matmul` | 33.858 | **33.747** | 33.760 | 75.264 | 3131.825 |
| `json_parse` | **8.601** | 8.887 | 11.783 | 35.986 | 37.239 |
| `nbody` | 41.030 | 40.887 | **39.103** | 103.414 | 2985.771 |

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
| _(floor: empty program)_ | _2.588_ | _79.051_ | _**81.639**_ | _57.735_ | _64.392_ |
| `lcg` | 2.682 | 83.071 | **85.753** | 65.965 | 68.436 |
| `packet_classifier` | 2.777 | 85.739 | **88.516** | 69.841 | 71.089 |
| `ring_write` | 2.894 | 87.775 | **90.669** | 69.650 | 70.358 |
| `histogram_bins` | 2.929 | 89.488 | **92.417** | 70.075 | 72.138 |
| `prefix_scan` | 2.997 | 90.334 | **93.331** | 71.612 | 72.290 |
| `binary_search` | 3.056 | 89.774 | **92.830** | 73.032 | 75.265 |
| `sort_window` | 3.100 | 96.695 | **99.795** | 76.063 | 78.541 |
| `bloom_filter` | 3.302 | 94.881 | **98.183** | 77.397 | 74.652 |
| `hash_join` | 5.466 | 214.093 | **219.559** | 121.077 | 112.708 |
| `sieve` | 3.011 | 90.390 | **93.401** | 78.343 | 82.481 |
| `fib` | 2.710 | 83.420 | **86.130** | 66.335 | 67.134 |
| `collatz` | 2.857 | 87.231 | **90.088** | 67.617 | 69.322 |
| `matmul` | 3.182 | 95.815 | **98.997** | 79.637 | 91.821 |
| `json_parse` | 40.135 | 514.008 | **554.143** | 123.462 | 177.527 |
| `nbody` | 4.223 | 107.046 | **111.269** | 96.421 | 92.201 |

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
