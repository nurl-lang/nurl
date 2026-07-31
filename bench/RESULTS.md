# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T15:46:56Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `96dfaa1ee3e54e2d1e951146ebd305cddb8e0ea6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30643962364 |
| NURL | `v0.29.0-91-g96dfaa1` |
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
| _(floor: empty program)_ | _1.808_ | _1.909_ | _2.058_ | _25.942_ | _18.739_ |
| `lcg` | **44.410** | 44.584 | 44.614 | 1840.854 | 5413.167 |
| `packet_classifier` | **63.726** | 63.818 | 64.032 | 157.373 | 5235.353 |
| `ring_write` | **47.895** | 47.928 | 48.141 | 74.424 | 7407.419 |
| `histogram_bins` | **44.899** | 44.930 | 45.118 | 75.721 | 6900.451 |
| `prefix_scan` | **24.669** | 24.756 | 24.930 | 71.630 | 4788.626 |
| `binary_search` | **36.046** | 36.091 | 46.353 | 113.398 | 6647.425 |
| `sort_window` | 31.015 | 31.144 | **30.549** | 168.443 | 11151.889 |
| `bloom_filter` | **19.995** | 20.580 | 20.978 | 2812.557 | 7679.146 |
| `hash_join` | **29.406** | 31.100 | 31.427 | 3500.030 | 8277.268 |
| `sieve` | 21.324 | **20.847** | 20.926 | 74.055 | 3568.485 |
| `fib` | **28.210** | 33.530 | 29.711 | 144.306 | 1298.389 |
| `collatz` | **13.899** | 14.092 | 14.159 | 53.980 | 755.405 |
| `matmul` | **45.691** | 46.509 | 45.823 | 84.332 | 3357.921 |
| `json_parse` | **8.327** | 9.240 | 12.351 | 40.225 | 39.430 |
| `nbody` | 46.284 | 46.393 | **44.218** | 96.731 | 3245.240 |

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
| _(floor: empty program)_ | _3.454_ | _91.637_ | _**95.091**_ | _67.705_ | _66.371_ |
| `lcg` | 3.568 | 96.532 | **100.100** | 75.946 | 77.345 |
| `packet_classifier` | 3.734 | 98.261 | **101.995** | 76.685 | 74.331 |
| `ring_write` | 3.939 | 98.463 | **102.402** | 77.702 | 78.168 |
| `histogram_bins` | 4.084 | 101.832 | **105.916** | 79.471 | 82.033 |
| `prefix_scan` | 4.284 | 103.487 | **107.771** | 82.450 | 78.218 |
| `binary_search` | 4.535 | 101.917 | **106.452** | 78.298 | 80.178 |
| `sort_window` | 4.589 | 108.801 | **113.390** | 83.901 | 86.367 |
| `bloom_filter` | 4.987 | 109.439 | **114.426** | 85.378 | 82.507 |
| `hash_join` | 9.843 | 216.221 | **226.064** | 124.723 | 121.478 |
| `sieve` | 4.326 | 104.277 | **108.603** | 86.619 | 88.223 |
| `fib` | 3.603 | 96.682 | **100.285** | 75.674 | 73.941 |
| `collatz` | 4.028 | 102.453 | **106.481** | 76.973 | 76.866 |
| `matmul` | 4.897 | 107.633 | **112.530** | 89.228 | 101.170 |
| `json_parse` | 79.993 | 709.670 | **789.663** | 128.690 | 190.528 |
| `nbody` | 7.367 | 118.835 | **126.202** | 103.182 | 99.780 |

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
