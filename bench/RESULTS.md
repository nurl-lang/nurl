# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-02T19:16:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `f4b4983fb6952b372c04cf676da12e86165b3bba` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30762834702 |
| NURL | `v0.30.0-46-gf4b4983f` |
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
| _(floor: empty program)_ | _1.734_ | _1.787_ | _1.993_ | _26.609_ | _18.728_ |
| `lcg` | **39.405** | 39.648 | 39.824 | 1918.987 | 5144.303 |
| `packet_classifier` | **56.741** | 56.842 | 56.940 | 163.273 | 4415.278 |
| `ring_write` | **42.655** | 42.858 | 42.921 | 69.339 | 6193.169 |
| `histogram_bins` | **40.043** | 41.720 | 40.395 | 68.390 | 5966.626 |
| `prefix_scan` | **22.135** | 22.329 | 22.571 | 68.062 | 4592.374 |
| `binary_search` | 40.365 | **38.896** | 43.720 | 108.411 | 6030.391 |
| `sort_window` | 27.707 | 27.823 | **27.224** | 199.834 | 11779.966 |
| `bloom_filter` | **18.360** | 18.801 | 19.128 | 2857.828 | 7778.566 |
| `hash_join` | **28.437** | 30.644 | 30.404 | 3437.819 | 8288.603 |
| `sieve` | 19.019 | **18.932** | 19.041 | 67.116 | 3394.972 |
| `fib` | **25.565** | 30.414 | 28.681 | 133.090 | 1382.267 |
| `collatz` | **12.624** | 12.644 | 12.892 | 52.024 | 712.856 |
| `matmul` | 34.096 | **34.077** | 34.242 | 77.830 | 3250.694 |
| `json_parse` | **9.041** | 9.132 | 12.229 | 37.772 | 39.787 |
| `nbody` | 41.299 | 41.266 | **39.439** | 103.631 | 3051.190 |

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
| _(floor: empty program)_ | _2.823_ | _83.060_ | _**85.883**_ | _64.383_ | _65.297_ |
| `lcg` | 2.920 | 89.458 | **92.378** | 70.369 | 72.520 |
| `packet_classifier` | 2.911 | 90.046 | **92.957** | 70.955 | 72.226 |
| `ring_write` | 3.029 | 91.721 | **94.750** | 72.895 | 74.227 |
| `histogram_bins` | 3.135 | 95.684 | **98.819** | 74.721 | 76.380 |
| `prefix_scan` | 3.097 | 98.026 | **101.123** | 76.578 | 75.992 |
| `binary_search` | 3.175 | 95.602 | **98.777** | 74.943 | 78.569 |
| `sort_window` | 3.204 | 102.706 | **105.910** | 80.213 | 83.012 |
| `bloom_filter` | 3.410 | 102.258 | **105.668** | 80.829 | 80.781 |
| `hash_join` | 5.561 | 218.957 | **224.518** | 124.558 | 114.259 |
| `sieve` | 3.066 | 95.524 | **98.590** | 80.536 | 82.805 |
| `fib` | 2.845 | 90.057 | **92.902** | 70.933 | 70.150 |
| `collatz` | 2.959 | 92.926 | **95.885** | 73.082 | 73.637 |
| `matmul` | 3.302 | 99.676 | **102.978** | 83.605 | 95.731 |
| `json_parse` | 40.702 | 537.483 | **578.185** | 132.106 | 187.821 |
| `nbody` | 4.386 | 113.159 | **117.545** | 101.869 | 98.154 |

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
