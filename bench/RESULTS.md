# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-10T09:23:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `35a70f006ba179fa2fbe28f4c854963cbb8c7ef1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31374033817 |
| NURL | `v0.36.0-47-g35a70f00` |
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
| _(floor: empty program)_ | _1.658_ | _1.739_ | _1.899_ | _23.213_ | _17.755_ |
| `lcg` | **39.485** | 39.593 | 39.741 | 1877.612 | 5095.000 |
| `packet_classifier` | 56.766 | **56.753** | 56.930 | 162.770 | 4465.413 |
| `ring_write` | **42.644** | 42.797 | 42.793 | 67.723 | 6476.032 |
| `histogram_bins` | 40.205 | 41.773 | **40.200** | 67.783 | 5938.215 |
| `prefix_scan` | **21.871** | 22.026 | 22.090 | 65.921 | 4478.688 |
| `binary_search` | 40.383 | **38.650** | 43.636 | 107.945 | 7728.344 |
| `sort_window` | **27.526** | 28.040 | 33.047 | 200.843 | 11276.358 |
| `bloom_filter` | **18.049** | 18.309 | 18.591 | 2842.438 | 7417.166 |
| `hash_join` | **28.414** | 30.366 | 30.131 | 3415.921 | 8268.206 |
| `sieve` | 20.472 | **19.976** | 20.338 | 67.551 | 3454.806 |
| `fib` | **25.374** | 30.170 | 28.341 | 131.755 | 1352.573 |
| `collatz` | **12.461** | 12.516 | 12.516 | 51.327 | 712.344 |
| `matmul` | 33.720 | **33.638** | 33.888 | 76.921 | 3191.376 |
| `json_parse` | 42.392 | **8.933** | 11.812 | 35.430 | 37.870 |
| `nbody` | 41.122 | 40.955 | **39.146** | 101.018 | 3072.359 |

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
| _(floor: empty program)_ | _2.776_ | _83.320_ | _**86.096**_ | _59.366_ | _61.085_ |
| `lcg` | 2.856 | 90.983 | **93.839** | 67.728 | 70.216 |
| `packet_classifier` | 3.046 | 92.152 | **95.198** | 70.566 | 69.881 |
| `ring_write` | 3.003 | 92.830 | **95.833** | 70.219 | 71.764 |
| `histogram_bins` | 3.085 | 96.154 | **99.239** | 76.804 | 74.981 |
| `prefix_scan` | 3.049 | 96.536 | **99.585** | 74.943 | 73.981 |
| `binary_search` | 3.209 | 95.743 | **98.952** | 71.373 | 78.054 |
| `sort_window` | 3.215 | 103.253 | **106.468** | 78.019 | 80.054 |
| `bloom_filter` | 3.462 | 101.076 | **104.538** | 77.757 | 75.898 |
| `hash_join` | 5.540 | 216.680 | **222.220** | 122.905 | 112.680 |
| `sieve` | 3.083 | 95.133 | **98.216** | 80.666 | 78.714 |
| `fib` | 2.780 | 86.051 | **88.831** | 67.151 | 68.428 |
| `collatz` | 2.949 | 89.666 | **92.615** | 69.385 | 70.303 |
| `matmul` | 3.298 | 98.599 | **101.897** | 81.812 | 92.126 |
| `json_parse` | 42.666 | 546.360 | **589.026** | 124.927 | 178.669 |
| `nbody` | 4.404 | 110.740 | **115.144** | 98.426 | 94.975 |

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
