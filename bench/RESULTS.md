# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T05:15:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a564b0c159fc76d2106053638984e01c34db2956` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31241106675 |
| NURL | `v0.35.1-22-ga564b0c1` |
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
| _(floor: empty program)_ | _1.816_ | _1.869_ | _2.077_ | _24.311_ | _17.789_ |
| `lcg` | **44.305** | 44.402 | 44.581 | 1829.532 | 5453.707 |
| `packet_classifier` | **63.801** | 63.831 | 63.944 | 157.842 | 4669.340 |
| `ring_write` | **47.964** | 47.979 | 48.080 | 72.912 | 6492.356 |
| `histogram_bins` | **44.762** | 44.870 | 45.186 | 74.530 | 7136.890 |
| `prefix_scan` | **24.610** | 24.756 | 24.867 | 70.906 | 4849.226 |
| `binary_search` | **35.696** | 36.012 | 46.081 | 110.773 | 6414.149 |
| `sort_window` | 30.971 | 30.980 | **30.333** | 168.345 | 11058.418 |
| `bloom_filter` | **19.910** | 20.499 | 20.875 | 2776.687 | 7875.340 |
| `hash_join` | **29.287** | 30.887 | 31.362 | 3401.715 | 8109.729 |
| `sieve` | 20.690 | **20.210** | 20.259 | 70.843 | 3632.525 |
| `fib` | **28.058** | 33.494 | 29.540 | 141.971 | 1286.802 |
| `collatz` | **13.954** | 13.984 | 14.054 | 51.269 | 755.710 |
| `matmul` | 46.469 | **45.934** | 46.551 | 83.083 | 3327.980 |
| `json_parse` | 45.811 | **9.084** | 12.366 | 37.943 | 37.934 |
| `nbody` | 46.283 | 46.424 | **44.234** | 95.910 | 3277.916 |

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
| _(floor: empty program)_ | _2.957_ | _87.522_ | _**90.479**_ | _63.352_ | _65.349_ |
| `lcg` | 3.055 | 92.427 | **95.482** | 71.808 | 71.988 |
| `packet_classifier` | 3.149 | 94.039 | **97.188** | 73.140 | 72.242 |
| `ring_write` | 3.233 | 95.127 | **98.360** | 73.740 | 78.983 |
| `histogram_bins` | 3.336 | 97.774 | **101.110** | 75.703 | 75.714 |
| `prefix_scan` | 3.347 | 99.824 | **103.171** | 76.979 | 75.834 |
| `binary_search` | 3.469 | 99.008 | **102.477** | 74.617 | 79.170 |
| `sort_window` | 3.563 | 105.008 | **108.571** | 80.498 | 82.972 |
| `bloom_filter` | 3.732 | 103.738 | **107.470** | 81.982 | 79.328 |
| `hash_join` | 5.733 | 209.236 | **214.969** | 121.478 | 120.021 |
| `sieve` | 3.355 | 99.680 | **103.035** | 82.803 | 83.693 |
| `fib` | 3.083 | 92.335 | **95.418** | 72.000 | 71.526 |
| `collatz` | 3.277 | 96.643 | **99.920** | 73.365 | 74.608 |
| `matmul` | 3.580 | 103.891 | **107.471** | 84.934 | 95.920 |
| `json_parse` | 40.117 | 519.464 | **559.581** | 125.195 | 184.795 |
| `nbody` | 4.628 | 114.262 | **118.890** | 99.147 | 97.021 |

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
