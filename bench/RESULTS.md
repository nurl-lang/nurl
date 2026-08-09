# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-09T18:36:25Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `de25cfe68164aca30947425f83f4238e9b1a7a35` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31329303900 |
| NURL | `v0.36.0-29-gde25cfe6` |
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
| _(floor: empty program)_ | _1.248_ | _1.246_ | _1.329_ | _16.070_ | _11.325_ |
| `lcg` | 30.212 | 30.174 | **30.164** | 1172.390 | 3169.790 |
| `packet_classifier` | **48.760** | 52.114 | 52.138 | 125.321 | 2779.121 |
| `ring_write` | 32.848 | 33.151 | **32.669** | 48.764 | 4245.495 |
| `histogram_bins` | 31.215 | 31.216 | **31.182** | 50.762 | 4073.900 |
| `prefix_scan` | **16.609** | 16.923 | 16.981 | 49.691 | 2746.067 |
| `binary_search` | 25.183 | **22.260** | 32.989 | 82.709 | 4519.859 |
| `sort_window` | **31.494** | 38.623 | 35.723 | 151.236 | 6712.532 |
| `bloom_filter` | 12.056 | **10.944** | 11.109 | 1838.696 | 4975.535 |
| `hash_join` | **18.385** | 19.760 | 20.060 | 2224.407 | 5695.835 |
| `sieve` | 33.098 | **32.436** | 32.784 | 66.320 | 1991.513 |
| `fib` | **17.477** | 20.483 | 19.341 | 83.071 | 667.943 |
| `collatz` | **11.340** | 11.477 | 12.135 | 44.083 | 420.413 |
| `matmul` | 15.291 | **15.085** | 15.194 | 54.153 | 1962.947 |
| `json_parse` | 25.541 | **5.777** | 7.145 | 23.959 | 24.059 |
| `nbody` | 23.505 | 23.695 | **21.823** | 61.833 | 1677.684 |

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
| _(floor: empty program)_ | _1.931_ | _54.225_ | _**56.156**_ | _35.984_ | _49.095_ |
| `lcg` | 1.923 | 55.197 | **57.120** | 40.651 | 53.951 |
| `packet_classifier` | 2.035 | 56.237 | **58.272** | 40.487 | 50.758 |
| `ring_write` | 2.040 | 57.707 | **59.747** | 42.460 | 51.510 |
| `histogram_bins` | 2.148 | 58.533 | **60.681** | 44.340 | 53.497 |
| `prefix_scan` | 2.191 | 61.163 | **63.354** | 43.885 | 54.914 |
| `binary_search` | 2.262 | 57.837 | **60.099** | 43.751 | 55.320 |
| `sort_window` | 2.402 | 62.977 | **65.379** | 271.231 | 62.535 |
| `bloom_filter` | 2.401 | 61.277 | **63.678** | 44.046 | 55.316 |
| `hash_join` | 3.807 | 131.284 | **135.091** | 78.850 | 84.679 |
| `sieve` | 2.171 | 62.226 | **64.397** | 52.054 | 61.593 |
| `fib` | 2.060 | 53.460 | **55.520** | 38.205 | 49.223 |
| `collatz` | 2.122 | 58.190 | **60.312** | 43.560 | 54.089 |
| `matmul` | 2.612 | 69.381 | **71.993** | 53.645 | 77.694 |
| `json_parse` | 28.244 | 342.583 | **370.827** | 95.361 | 137.412 |
| `nbody` | 3.029 | 72.863 | **75.892** | 59.356 | 69.771 |

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
