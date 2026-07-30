# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T20:53:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `75df538fc875fa763485b897ee7b0022b4ad24a4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30580759565 |
| NURL | `v0.29.0-65-g75df538` |
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
| _(floor: empty program)_ | _1.785_ | _1.862_ | _1.981_ | _24.341_ | _18.059_ |
| `lcg` | **44.261** | 44.303 | 44.482 | 1825.073 | 5296.188 |
| `packet_classifier` | 63.903 | **63.855** | 64.021 | 158.609 | 4616.417 |
| `ring_write` | 47.840 | **47.825** | 48.116 | 74.339 | 6959.724 |
| `histogram_bins` | **44.804** | 44.950 | 45.069 | 76.001 | 6310.923 |
| `prefix_scan` | **24.646** | 24.694 | 24.909 | 72.283 | 4845.510 |
| `binary_search` | **35.810** | 35.927 | 46.177 | 112.103 | 6317.613 |
| `sort_window` | 30.853 | 31.038 | **30.495** | 166.310 | 11939.986 |
| `bloom_filter` | **19.906** | 20.568 | 20.781 | 2749.081 | 7797.809 |
| `hash_join` | **29.255** | 30.891 | 31.185 | 3464.145 | 8203.270 |
| `sieve` | 20.539 | **20.223** | 20.287 | 71.110 | 3544.203 |
| `fib` | **28.057** | 33.410 | 29.448 | 141.723 | 1287.977 |
| `collatz` | 13.952 | **13.927** | 13.939 | 51.365 | 754.165 |
| `matmul` | **44.992** | 45.402 | 45.588 | 85.572 | 3425.346 |
| `json_parse` | **8.386** | 9.133 | 12.459 | 38.283 | 38.434 |
| `nbody` | 46.236 | 46.435 | **44.215** | 96.487 | 3279.713 |

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
| _(floor: empty program)_ | _3.447_ | _89.796_ | _**93.243**_ | _64.773_ | _64.970_ |
| `lcg` | 3.500 | 91.837 | **95.337** | 71.786 | 73.351 |
| `packet_classifier` | 3.714 | 96.030 | **99.744** | 75.132 | 73.592 |
| `ring_write` | 3.857 | 96.106 | **99.963** | 75.128 | 74.959 |
| `histogram_bins` | 4.022 | 99.699 | **103.721** | 78.053 | 78.068 |
| `prefix_scan` | 4.156 | 101.506 | **105.662** | 79.632 | 78.223 |
| `binary_search` | 4.396 | 99.562 | **103.958** | 76.368 | 83.613 |
| `sort_window` | 4.515 | 107.059 | **111.574** | 83.286 | 85.421 |
| `bloom_filter` | 4.790 | 103.603 | **108.393** | 82.084 | 80.458 |
| `hash_join` | 9.479 | 208.514 | **217.993** | 122.824 | 115.507 |
| `sieve` | 4.102 | 98.739 | **102.841** | 82.864 | 84.341 |
| `fib` | 3.528 | 93.705 | **97.233** | 73.191 | 71.725 |
| `collatz` | 3.937 | 97.888 | **101.825** | 73.380 | 75.364 |
| `matmul` | 4.748 | 101.808 | **106.556** | 84.904 | 97.836 |
| `json_parse` | 77.880 | 706.184 | **784.064** | 125.108 | 187.408 |
| `nbody` | 7.281 | 114.750 | **122.031** | 100.279 | 99.946 |

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
