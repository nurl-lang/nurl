# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-03T06:30:03Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `380ea8e4613261933eed2a67ca167f38eeac18b6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30790165733 |
| NURL | `v0.32.0` |
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
| _(floor: empty program)_ | _1.659_ | _1.766_ | _1.875_ | _22.720_ | _17.003_ |
| `lcg` | **39.208** | 39.381 | 39.384 | 1874.345 | 6019.356 |
| `packet_classifier` | **56.410** | 56.511 | 56.633 | 162.279 | 4432.724 |
| `ring_write` | **42.300** | 42.411 | 42.522 | 65.616 | 6396.236 |
| `histogram_bins` | **39.662** | 41.421 | 39.875 | 64.727 | 6090.057 |
| `prefix_scan` | 21.880 | **21.856** | 22.037 | 64.490 | 4514.129 |
| `binary_search` | 40.080 | **38.418** | 43.357 | 105.066 | 6657.090 |
| `sort_window` | 27.390 | 27.437 | **26.928** | 195.787 | 12151.980 |
| `bloom_filter` | **18.108** | 18.220 | 18.583 | 2811.814 | 7624.630 |
| `hash_join` | **28.150** | 30.262 | 30.010 | 3432.889 | 8203.840 |
| `sieve` | 20.255 | **19.840** | 20.230 | 65.930 | 3403.095 |
| `fib` | **25.285** | 30.059 | 28.285 | 130.470 | 1360.801 |
| `collatz` | **12.470** | 12.484 | 12.634 | 48.411 | 720.674 |
| `matmul` | 33.707 | **33.683** | 33.807 | 75.315 | 3104.677 |
| `json_parse` | **8.691** | 8.818 | 11.842 | 34.482 | 36.784 |
| `nbody` | 40.851 | 40.904 | **39.078** | 99.376 | 3142.980 |

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
| _(floor: empty program)_ | _2.637_ | _76.485_ | _**79.122**_ | _55.329_ | _59.888_ |
| `lcg` | 2.704 | 81.842 | **84.546** | 64.007 | 68.021 |
| `packet_classifier` | 2.860 | 82.754 | **85.614** | 66.321 | 66.719 |
| `ring_write` | 2.870 | 83.909 | **86.779** | 66.153 | 68.909 |
| `histogram_bins` | 2.912 | 87.377 | **90.289** | 68.904 | 71.440 |
| `prefix_scan` | 2.973 | 88.327 | **91.300** | 70.679 | 72.150 |
| `binary_search` | 3.083 | 87.866 | **90.949** | 67.762 | 74.093 |
| `sort_window` | 3.133 | 93.969 | **97.102** | 74.099 | 78.697 |
| `bloom_filter` | 3.302 | 92.710 | **96.012** | 75.109 | 74.447 |
| `hash_join` | 5.360 | 207.235 | **212.595** | 117.368 | 108.923 |
| `sieve` | 2.987 | 88.014 | **91.001** | 76.474 | 78.203 |
| `fib` | 2.741 | 80.965 | **83.706** | 64.557 | 66.378 |
| `collatz` | 2.882 | 85.017 | **87.899** | 66.659 | 69.074 |
| `matmul` | 3.160 | 92.031 | **95.191** | 78.473 | 90.620 |
| `json_parse` | 40.204 | 508.557 | **548.761** | 120.909 | 176.072 |
| `nbody` | 4.203 | 103.638 | **107.841** | 94.660 | 91.375 |

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
