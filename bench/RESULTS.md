# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-17T11:40:23Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `0ffc7f1d3f9af4a49cddb8442aebf4eefa79fa02` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32025684408 |
| NURL | `v0.44.2-12-g0ffc7f1d` |
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
| _(floor: empty program)_ | _1.801_ | _1.863_ | _2.076_ | _25.663_ | _18.317_ |
| `lcg` | **44.270** | 44.348 | 44.555 | 1818.509 | 5506.164 |
| `packet_classifier` | **63.774** | 63.821 | 64.015 | 158.318 | 4773.329 |
| `ring_write` | **47.832** | 47.902 | 48.031 | 72.190 | 7165.289 |
| `histogram_bins` | **44.777** | 44.860 | 45.012 | 74.060 | 6222.453 |
| `prefix_scan` | **24.709** | 24.727 | 24.891 | 72.391 | 4832.244 |
| `binary_search` | **34.342** | 36.101 | 46.266 | 111.979 | 6637.839 |
| `sort_window` | **30.381** | 31.040 | 30.588 | 167.220 | 10970.947 |
| `bloom_filter` | **19.950** | 20.616 | 20.876 | 2756.779 | 7786.461 |
| `hash_join` | **28.084** | 31.166 | 31.439 | 3454.030 | 8225.978 |
| `sieve` | 20.874 | **20.841** | 20.928 | 70.760 | 3700.860 |
| `fib` | **28.264** | 33.630 | 29.652 | 145.720 | 1306.055 |
| `collatz` | **14.005** | 14.008 | 14.080 | 52.510 | 751.874 |
| `matmul` | **45.835** | 46.878 | 48.146 | 84.209 | 3465.291 |
| `json_parse` | **9.027** | 9.189 | 12.387 | 38.406 | 40.058 |
| `nbody` | **26.955** | 46.564 | 44.297 | 95.382 | 3364.472 |

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
| _(floor: empty program)_ | _3.201_ | _104.397_ | _**107.598**_ | _65.805_ | _68.720_ | _66.838_ |
| `lcg` | 3.391 | 104.113 | **107.504** | 67.028 | 74.283 | 74.533 |
| `packet_classifier` | 3.475 | 103.362 | **106.837** | 65.423 | 75.239 | 74.639 |
| `ring_write` | 3.518 | 100.946 | **104.464** | 63.918 | 75.416 | 75.587 |
| `histogram_bins` | 3.616 | 121.534 | **125.150** | 64.449 | 77.039 | 77.893 |
| `prefix_scan` | 3.704 | 107.879 | **111.583** | 64.823 | 78.777 | 77.261 |
| `binary_search` | 3.842 | 111.590 | **115.432** | 64.927 | 75.628 | 79.938 |
| `sort_window` | 3.942 | 116.262 | **120.204** | 66.919 | 82.380 | 89.978 |
| `bloom_filter` | 4.111 | 112.743 | **116.854** | 66.000 | 83.219 | 81.665 |
| `hash_join` | 6.587 | 255.905 | **262.492** | 70.328 | 123.705 | 116.582 |
| `sieve` | 3.717 | 107.429 | **111.146** | 65.212 | 83.670 | 86.689 |
| `fib` | 3.382 | 103.670 | **107.052** | 65.390 | 74.291 | 75.846 |
| `collatz` | 3.554 | 106.219 | **109.773** | 66.571 | 77.289 | 77.669 |
| `matmul` | 3.945 | 111.489 | **115.434** | 66.102 | 87.895 | 101.462 |
| `json_parse` | 51.590 | 426.874 | **478.464** | 116.727 | 126.861 | 188.653 |
| `nbody` | 5.296 | 135.124 | **140.420** | 69.997 | 103.115 | 100.405 |

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
