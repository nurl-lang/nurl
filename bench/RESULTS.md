# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-14T18:47:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373440 KiB |
| Commit | `16f4bf2f90b6f072cc682b2c5bd0f24439620636` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31829939842 |
| NURL | `v0.42.0-14-g16f4bf2f` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
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
| _(floor: empty program)_ | _1.733_ | _1.941_ | _2.057_ | _23.955_ | _18.223_ |
| `lcg` | **39.647** | 39.788 | 39.825 | 2061.626 | 5233.045 |
| `packet_classifier` | 56.904 | **56.801** | 56.939 | 163.601 | 4303.055 |
| `ring_write` | **42.876** | 43.000 | 42.969 | 72.170 | 6365.281 |
| `histogram_bins` | **39.953** | 41.780 | 40.329 | 67.208 | 7658.453 |
| `prefix_scan` | **22.572** | 22.669 | 22.624 | 69.207 | 4489.074 |
| `binary_search` | **36.983** | 39.023 | 43.760 | 110.254 | 6693.471 |
| `sort_window` | **27.113** | 27.898 | 27.375 | 199.859 | 11425.251 |
| `bloom_filter` | **18.445** | 18.611 | 18.867 | 2865.221 | 7749.439 |
| `hash_join` | **27.859** | 30.803 | 30.398 | 3495.234 | 8416.583 |
| `sieve` | 19.776 | **18.840** | 18.994 | 69.291 | 3367.710 |
| `fib` | **25.505** | 30.427 | 29.029 | 134.473 | 1343.455 |
| `collatz` | 12.893 | **12.875** | 13.049 | 51.929 | 717.701 |
| `matmul` | **33.866** | 33.872 | 34.195 | 78.204 | 3204.921 |
| `json_parse` | 9.432 | **9.096** | 12.170 | 39.949 | 40.420 |
| `nbody` | **25.571** | 41.237 | 39.493 | 101.496 | 3030.903 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns: a cold compile, measured
against a wiped cache exactly as C and Rust pay their full cost every
time. **NURL rebuild** is the same compile again with the ThinLTO
cache warm — `nurl.sh`'s default on Linux (docs/BUILDING.md → The
ThinLTO cache) — which is what every build after the first costs; C
and Rust have no default equivalent (`ccache`/`sccache` are opt-in
add-ons). The floor row is what each toolchain costs for a program
that does nothing — for NURL that is dominated by the LTO link every
NURL binary pays for, so subtract it to read the marginal cost of the
benchmark itself. Node and Python have no column here: they compile
at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | NURL rebuild | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.970_ | _92.903_ | _**95.873**_ | _60.785_ | _60.063_ | _66.003_ |
| `lcg` | 3.066 | 103.637 | **106.703** | 71.387 | 75.078 | 75.432 |
| `packet_classifier` | 3.106 | 98.918 | **102.024** | 62.325 | 71.658 | 73.053 |
| `ring_write` | 3.153 | 100.528 | **103.681** | 63.882 | 78.287 | 74.251 |
| `histogram_bins` | 3.435 | 122.084 | **125.519** | 63.870 | 77.655 | 76.575 |
| `prefix_scan` | 3.668 | 110.101 | **113.769** | 75.725 | 76.716 | 76.232 |
| `binary_search` | 3.568 | 110.360 | **113.928** | 63.345 | 73.672 | 79.098 |
| `sort_window` | 3.791 | 112.650 | **116.441** | 63.442 | 78.881 | 83.226 |
| `bloom_filter` | 3.723 | 114.897 | **118.620** | 67.190 | 82.482 | 77.498 |
| `hash_join` | 6.625 | 275.743 | **282.368** | 69.183 | 128.340 | 120.518 |
| `sieve` | 3.408 | 109.816 | **113.224** | 67.820 | 87.000 | 90.975 |
| `fib` | 3.092 | 100.525 | **103.617** | 63.154 | 70.977 | 70.774 |
| `collatz` | 3.251 | 101.866 | **105.117** | 62.960 | 73.954 | 73.850 |
| `matmul` | 3.669 | 107.823 | **111.492** | 63.302 | 94.355 | 94.999 |
| `json_parse` | 49.014 | 441.275 | **490.289** | 108.521 | 125.794 | 180.581 |
| `nbody` | 4.968 | 143.465 | **148.433** | 65.699 | 101.777 | 93.359 |

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
