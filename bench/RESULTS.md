# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T03:39:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `74565bac6ee62d3cc6512f77609e3f477d42634a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31237497789 |
| NURL | `v0.35.1-13-g74565bac` |
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
| _(floor: empty program)_ | _1.657_ | _1.725_ | _1.852_ | _22.449_ | _17.352_ |
| `lcg` | **39.366** | 39.479 | 39.633 | 1876.664 | 5215.014 |
| `packet_classifier` | **56.499** | 56.679 | 56.703 | 162.420 | 4460.820 |
| `ring_write` | 42.530 | **42.491** | 42.610 | 65.138 | 6559.270 |
| `histogram_bins` | **39.789** | 41.339 | 40.031 | 66.153 | 6314.889 |
| `prefix_scan` | **21.953** | 22.090 | 22.087 | 65.955 | 4583.142 |
| `binary_search` | 39.872 | **38.488** | 43.291 | 107.023 | 6828.767 |
| `sort_window` | 27.436 | 27.464 | **26.914** | 197.824 | 12322.551 |
| `bloom_filter` | **18.115** | 18.300 | 18.636 | 2829.694 | 7510.947 |
| `hash_join` | **28.387** | 30.239 | 30.054 | 3422.282 | 8375.297 |
| `sieve` | 20.701 | 20.625 | **20.526** | 65.910 | 3258.937 |
| `fib` | **25.470** | 30.058 | 28.433 | 132.480 | 1365.690 |
| `collatz` | 12.438 | **12.428** | 12.559 | 49.330 | 715.587 |
| `matmul` | 33.752 | **33.575** | 33.972 | 75.134 | 3278.158 |
| `json_parse` | 42.293 | **8.799** | 11.801 | 36.663 | 37.451 |
| `nbody` | 40.963 | 41.064 | **39.145** | 102.258 | 3038.490 |

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
| _(floor: empty program)_ | _2.666_ | _84.129_ | _**86.795**_ | _58.601_ | _60.712_ |
| `lcg` | 2.734 | 85.615 | **88.349** | 65.867 | 68.450 |
| `packet_classifier` | 2.786 | 86.976 | **89.762** | 66.940 | 67.070 |
| `ring_write` | 2.934 | 89.042 | **91.976** | 67.918 | 69.947 |
| `histogram_bins` | 2.976 | 91.790 | **94.766** | 70.034 | 72.434 |
| `prefix_scan` | 2.984 | 90.711 | **93.695** | 71.555 | 72.298 |
| `binary_search` | 3.087 | 89.846 | **92.933** | 68.101 | 73.400 |
| `sort_window` | 3.182 | 97.853 | **101.035** | 74.641 | 78.744 |
| `bloom_filter` | 3.346 | 97.522 | **100.868** | 75.941 | 100.967 |
| `hash_join` | 5.378 | 211.685 | **217.063** | 118.345 | 110.472 |
| `sieve` | 2.975 | 91.794 | **94.769** | 77.528 | 78.341 |
| `fib` | 2.783 | 83.946 | **86.729** | 65.486 | 68.781 |
| `collatz` | 2.889 | 88.000 | **90.889** | 67.403 | 69.571 |
| `matmul` | 3.262 | 97.521 | **100.783** | 80.204 | 94.278 |
| `json_parse` | 40.866 | 539.791 | **580.657** | 123.551 | 185.862 |
| `nbody` | 4.198 | 106.607 | **110.805** | 97.642 | 92.522 |

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
