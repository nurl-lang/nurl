# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T07:23:44Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `e8f0047441bd6497459dfe783d9654f273c081b8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31677256835 |
| NURL | `v0.39.0-31-ge8f00474` |
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
| _(floor: empty program)_ | _1.668_ | _1.741_ | _1.908_ | _23.517_ | _17.115_ |
| `lcg` | **39.374** | 39.454 | 39.626 | 1880.385 | 5090.876 |
| `packet_classifier` | **56.702** | 56.709 | 56.775 | 162.790 | 4421.980 |
| `ring_write` | **42.493** | 42.528 | 42.690 | 68.406 | 6205.245 |
| `histogram_bins` | **39.895** | 41.487 | 40.084 | 68.092 | 6656.034 |
| `prefix_scan` | **21.908** | 21.999 | 22.129 | 65.496 | 4647.192 |
| `binary_search` | 40.119 | **38.699** | 43.625 | 106.925 | 6325.623 |
| `sort_window` | 27.474 | 27.554 | **27.096** | 199.026 | 12381.582 |
| `bloom_filter` | **18.086** | 18.303 | 18.649 | 2856.289 | 7759.196 |
| `hash_join` | **28.258** | 30.514 | 30.230 | 3442.203 | 8295.637 |
| `sieve` | 20.559 | 20.592 | **20.406** | 67.663 | 3215.350 |
| `fib` | **25.295** | 30.071 | 28.370 | 132.789 | 1372.581 |
| `collatz` | **12.533** | 12.537 | 12.609 | 49.709 | 711.003 |
| `matmul` | 33.795 | **33.719** | 33.984 | 76.637 | 3140.990 |
| `json_parse` | 8.983 | **8.856** | 11.783 | 36.023 | 38.176 |
| `nbody` | 41.164 | 41.056 | **39.203** | 101.423 | 3072.269 |

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
| _(floor: empty program)_ | _2.772_ | _83.784_ | _**86.556**_ | _60.813_ | _66.371_ |
| `lcg` | 2.887 | 88.158 | **91.045** | 68.954 | 72.124 |
| `packet_classifier` | 2.985 | 91.781 | **94.766** | 69.113 | 72.077 |
| `ring_write` | 3.091 | 92.137 | **95.228** | 71.079 | 71.746 |
| `histogram_bins` | 3.131 | 93.902 | **97.033** | 73.051 | 73.607 |
| `prefix_scan` | 3.209 | 96.065 | **99.274** | 76.009 | 73.586 |
| `binary_search` | 3.351 | 96.126 | **99.477** | 72.579 | 75.481 |
| `sort_window` | 3.486 | 102.807 | **106.293** | 76.870 | 79.372 |
| `bloom_filter` | 3.561 | 99.016 | **102.577** | 79.883 | 75.329 |
| `hash_join` | 5.846 | 213.897 | **219.743** | 120.977 | 112.162 |
| `sieve` | 3.184 | 94.253 | **97.437** | 80.985 | 79.712 |
| `fib` | 2.969 | 86.755 | **89.724** | 69.744 | 68.056 |
| `collatz` | 3.086 | 90.866 | **93.952** | 70.938 | 71.921 |
| `matmul` | 3.412 | 99.303 | **102.715** | 83.492 | 94.488 |
| `json_parse` | 45.162 | 542.069 | **587.231** | 123.920 | 180.170 |
| `nbody` | 4.576 | 113.913 | **118.489** | 99.092 | 94.407 |

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
