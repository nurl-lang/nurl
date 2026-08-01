# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T12:33:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `f8f0308277dcef6aed07a728ecdbc6f8d5bbbec2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30699751801 |
| NURL | `v0.30.0-17-gf8f0308` |
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
| _(floor: empty program)_ | _1.658_ | _1.698_ | _1.866_ | _22.551_ | _16.948_ |
| `lcg` | **39.261** | 39.302 | 39.374 | 1879.140 | 5131.454 |
| `packet_classifier` | 56.583 | **56.486** | 56.832 | 161.587 | 4840.840 |
| `ring_write` | **42.379** | 42.579 | 42.547 | 66.903 | 6462.125 |
| `histogram_bins` | **39.757** | 41.426 | 40.057 | 66.182 | 6178.672 |
| `prefix_scan` | **21.943** | 21.999 | 22.082 | 64.809 | 4448.103 |
| `binary_search` | 39.886 | **38.672** | 43.245 | 106.661 | 6031.608 |
| `sort_window` | 27.530 | 27.630 | **27.017** | 198.205 | 11231.619 |
| `bloom_filter` | **18.121** | 18.350 | 18.512 | 2853.546 | 7456.087 |
| `hash_join` | **28.254** | 30.408 | 30.058 | 3417.144 | 8450.757 |
| `sieve` | 19.230 | 20.417 | **18.300** | 67.225 | 3205.884 |
| `fib` | **25.298** | 30.136 | 28.316 | 131.537 | 1346.408 |
| `collatz` | 12.524 | **12.462** | 12.666 | 48.292 | 715.993 |
| `matmul` | **33.593** | 33.658 | 33.798 | 75.729 | 3113.332 |
| `json_parse` | **8.747** | 8.920 | 11.971 | 35.399 | 37.243 |
| `nbody` | 40.949 | 41.090 | **39.135** | 101.662 | 3019.968 |

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
| _(floor: empty program)_ | _2.686_ | _80.029_ | _**82.715**_ | _56.052_ | _61.462_ |
| `lcg` | 2.715 | 83.458 | **86.173** | 65.330 | 67.939 |
| `packet_classifier` | 2.796 | 85.791 | **88.587** | 67.362 | 68.019 |
| `ring_write` | 2.916 | 85.800 | **88.716** | 67.913 | 75.206 |
| `histogram_bins` | 3.009 | 88.999 | **92.008** | 70.230 | 70.171 |
| `prefix_scan` | 2.998 | 92.178 | **95.176** | 72.875 | 71.582 |
| `binary_search` | 3.094 | 90.567 | **93.661** | 69.501 | 74.640 |
| `sort_window` | 3.138 | 96.648 | **99.786** | 76.408 | 78.174 |
| `bloom_filter` | 3.398 | 99.260 | **102.658** | 79.273 | 75.584 |
| `hash_join` | 5.388 | 210.074 | **215.462** | 120.653 | 109.202 |
| `sieve` | 3.023 | 91.544 | **94.567** | 77.939 | 79.643 |
| `fib` | 2.777 | 83.588 | **86.365** | 67.655 | 68.206 |
| `collatz` | 2.894 | 88.486 | **91.380** | 68.524 | 69.970 |
| `matmul` | 3.222 | 96.106 | **99.328** | 80.954 | 91.967 |
| `json_parse` | 40.117 | 514.846 | **554.963** | 125.520 | 177.334 |
| `nbody` | 4.224 | 105.351 | **109.575** | 97.035 | 92.320 |

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
