# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T08:21:32Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `eedb5c156530337cd2279a473fdcdc91ecadbd14` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30891335173 |
| NURL | `v0.32.0-30-geedb5c15` |
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
| _(floor: empty program)_ | _1.253_ | _1.284_ | _1.410_ | _18.800_ | _14.037_ |
| `lcg` | 35.549 | 35.490 | **35.401** | 1321.172 | 3887.708 |
| `packet_classifier` | **56.288** | 61.875 | 59.483 | 146.750 | 3132.236 |
| `ring_write` | **38.803** | 39.221 | 38.944 | 59.103 | 4601.340 |
| `histogram_bins` | 37.127 | 36.681 | **36.204** | 59.450 | 4360.739 |
| `prefix_scan` | **19.681** | 19.742 | 19.925 | 58.309 | 3258.996 |
| `binary_search` | 30.479 | **27.750** | 39.546 | 97.913 | 4929.894 |
| `sort_window` | 37.434 | 46.081 | **35.837** | 163.064 | 8352.341 |
| `bloom_filter` | 13.452 | 12.916 | **12.884** | 2145.441 | 6027.778 |
| `hash_join` | **21.356** | 23.270 | 23.700 | 2687.245 | 6245.251 |
| `sieve` | 33.475 | **32.828** | 33.241 | 74.357 | 2365.913 |
| `fib` | 25.626 | 26.566 | **23.185** | 100.721 | 817.579 |
| `collatz` | **13.468** | 14.538 | 14.103 | 53.719 | 512.833 |
| `matmul` | 17.993 | **17.796** | 18.192 | 67.073 | 2267.248 |
| `json_parse` | **6.477** | 6.854 | 8.524 | 27.766 | 29.201 |
| `nbody` | 28.602 | 28.871 | **26.291** | 74.021 | 1903.669 |

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
| _(floor: empty program)_ | _2.030_ | _62.825_ | _**64.855**_ | _43.424_ | _52.574_ |
| `lcg` | 2.125 | 64.719 | **66.844** | 48.730 | 56.978 |
| `packet_classifier` | 2.262 | 65.534 | **67.796** | 57.970 | 57.270 |
| `ring_write` | 2.351 | 98.010 | **100.361** | 49.270 | 58.420 |
| `histogram_bins` | 2.359 | 68.323 | **70.682** | 51.672 | 61.196 |
| `prefix_scan` | 2.476 | 70.863 | **73.339** | 57.498 | 60.851 |
| `binary_search` | 2.516 | 71.218 | **73.734** | 50.442 | 64.603 |
| `sort_window` | 2.602 | 75.946 | **78.548** | 57.384 | 67.599 |
| `bloom_filter` | 2.706 | 77.713 | **80.419** | 56.734 | 65.084 |
| `hash_join` | 4.405 | 161.046 | **165.451** | 92.975 | 99.920 |
| `sieve` | 2.443 | 74.020 | **76.463** | 61.599 | 68.744 |
| `fib` | 2.238 | 72.446 | **74.684** | 53.738 | 59.889 |
| `collatz` | 2.588 | 74.284 | **76.872** | 53.787 | 61.336 |
| `matmul` | 2.662 | 75.649 | **78.311** | 63.389 | 81.828 |
| `json_parse` | 33.012 | 396.512 | **429.524** | 98.001 | 164.171 |
| `nbody` | 3.334 | 82.409 | **85.743** | 71.001 | 79.858 |

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
