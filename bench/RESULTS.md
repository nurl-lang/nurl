# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-17T13:20:59Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `049696c03bd9e77ea5179f84ad29147918c728a0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32034200287 |
| NURL | `v0.44.2-16-g049696c0` |
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
| _(floor: empty program)_ | _1.758_ | _1.810_ | _1.939_ | _25.506_ | _19.067_ |
| `lcg` | **39.748** | 39.822 | 39.830 | 2071.325 | 5162.974 |
| `packet_classifier` | **56.628** | 56.756 | 56.925 | 163.497 | 4430.253 |
| `ring_write` | **42.661** | 42.926 | 42.898 | 69.675 | 6333.064 |
| `histogram_bins` | **40.149** | 41.828 | 40.364 | 69.850 | 5827.563 |
| `prefix_scan` | **22.234** | 22.443 | 22.623 | 69.465 | 4458.572 |
| `binary_search` | **36.655** | 38.848 | 43.661 | 109.343 | 6702.476 |
| `sort_window` | 27.188 | 27.864 | **27.173** | 200.839 | 12274.338 |
| `bloom_filter` | **18.333** | 18.498 | 19.029 | 2906.822 | 7510.211 |
| `hash_join` | **27.642** | 30.805 | 30.345 | 3434.322 | 8533.478 |
| `sieve` | 19.903 | **18.755** | 19.122 | 69.726 | 4220.449 |
| `fib` | **25.575** | 30.485 | 28.768 | 135.494 | 1355.260 |
| `collatz` | **12.626** | 12.780 | 12.715 | 52.443 | 717.947 |
| `matmul` | 33.951 | **33.918** | 34.250 | 77.849 | 3059.622 |
| `json_parse` | 9.476 | **8.991** | 12.176 | 38.914 | 39.503 |
| `nbody` | **25.654** | 41.426 | 39.807 | 104.853 | 3067.565 |

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
| _(floor: empty program)_ | _2.996_ | _98.952_ | _**101.948**_ | _64.284_ | _64.186_ | _66.576_ |
| `lcg` | 3.146 | 100.279 | **103.425** | 62.547 | 72.787 | 75.193 |
| `packet_classifier` | 3.241 | 99.690 | **102.931** | 62.264 | 75.063 | 72.074 |
| `ring_write` | 3.286 | 100.644 | **103.930** | 62.378 | 73.148 | 74.626 |
| `histogram_bins` | 3.609 | 123.647 | **127.256** | 64.762 | 77.342 | 77.005 |
| `prefix_scan` | 3.479 | 108.111 | **111.590** | 63.470 | 77.385 | 75.263 |
| `binary_search` | 3.544 | 111.107 | **114.651** | 63.045 | 74.712 | 79.267 |
| `sort_window` | 3.806 | 115.410 | **119.216** | 64.451 | 81.366 | 91.603 |
| `bloom_filter` | 3.858 | 109.483 | **113.341** | 64.587 | 82.851 | 80.898 |
| `hash_join` | 6.371 | 262.421 | **268.792** | 65.616 | 125.139 | 117.284 |
| `sieve` | 3.565 | 108.284 | **111.849** | 63.415 | 84.930 | 84.183 |
| `fib` | 3.229 | 100.857 | **104.086** | 63.879 | 71.082 | 71.108 |
| `collatz` | 3.467 | 103.648 | **107.115** | 65.220 | 74.396 | 73.665 |
| `matmul` | 3.850 | 109.081 | **112.931** | 64.385 | 86.345 | 98.969 |
| `json_parse` | 53.388 | 452.214 | **505.602** | 114.899 | 132.340 | 195.201 |
| `nbody` | 5.149 | 135.613 | **140.762** | 63.989 | 102.463 | 98.762 |

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
