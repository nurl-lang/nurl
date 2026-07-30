# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T19:22:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `6c84587c1979263fcf35430ee49249241941a42d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30574165664 |
| NURL | `v0.29.0-59-g6c84587` |
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
| _(floor: empty program)_ | _1.222_ | _1.229_ | _1.354_ | _17.958_ | _12.709_ |
| `lcg` | 34.041 | 33.899 | **33.601** | 1164.323 | 3632.115 |
| `packet_classifier` | **55.698** | 59.939 | 60.834 | 145.048 | 2944.867 |
| `ring_write` | **37.212** | 37.792 | 37.544 | 59.072 | 4313.603 |
| `histogram_bins` | **35.674** | 35.943 | 35.808 | 59.638 | 4025.726 |
| `prefix_scan` | 18.552 | **18.418** | 19.030 | 57.292 | 2953.787 |
| `binary_search` | 29.026 | **25.563** | 39.918 | 95.166 | 4304.059 |
| `sort_window` | 35.459 | 42.850 | **33.466** | 150.648 | 7552.745 |
| `bloom_filter` | 12.183 | **12.119** | 12.200 | 2040.906 | 5472.087 |
| `hash_join` | **20.922** | 23.218 | 23.006 | 2525.499 | 5948.574 |
| `sieve` | 34.867 | 36.203 | **34.610** | 76.240 | 2214.007 |
| `fib` | **19.397** | 23.318 | 22.064 | 94.673 | 748.233 |
| `collatz` | **12.572** | 12.792 | 13.351 | 49.940 | 460.568 |
| `matmul` | **15.841** | 16.346 | 16.371 | 61.769 | 2020.853 |
| `json_parse` | **5.606** | 6.383 | 7.887 | 26.540 | 27.146 |
| `nbody` | 26.117 | 26.153 | **23.241** | 68.898 | 1723.890 |

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
| _(floor: empty program)_ | _2.239_ | _67.862_ | _**70.101**_ | _51.180_ | _52.337_ |
| `lcg` | 2.232 | 63.884 | **66.116** | 50.909 | 59.472 |
| `packet_classifier` | 2.482 | 72.272 | **74.754** | 55.763 | 60.868 |
| `ring_write` | 2.514 | 72.705 | **75.219** | 61.147 | 62.703 |
| `histogram_bins` | 2.691 | 76.564 | **79.255** | 59.085 | 66.077 |
| `prefix_scan` | 2.664 | 74.528 | **77.192** | 59.855 | 64.897 |
| `binary_search` | 2.862 | 73.154 | **76.016** | 53.595 | 63.276 |
| `sort_window` | 2.908 | 81.829 | **84.737** | 62.507 | 70.992 |
| `bloom_filter` | 3.232 | 79.086 | **82.318** | 62.472 | 68.914 |
| `hash_join` | 6.287 | 156.959 | **163.246** | 97.876 | 99.755 |
| `sieve` | 2.795 | 79.052 | **81.847** | 65.501 | 76.366 |
| `fib` | 2.408 | 71.880 | **74.288** | 55.576 | 59.662 |
| `collatz` | 2.598 | 72.173 | **74.771** | 53.805 | 61.120 |
| `matmul` | 3.274 | 77.005 | **80.279** | 60.495 | 77.461 |
| `json_parse` | 47.209 | 499.996 | **547.205** | 92.750 | 159.059 |
| `nbody` | 4.317 | 83.597 | **87.914** | 71.509 | 77.839 |

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
