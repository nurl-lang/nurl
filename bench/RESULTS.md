# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T11:30:37Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e081b0f3187b6889d81ab29e413264a7a9e6e06e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32363774372 |
| NURL | `v0.46.0-2-ge081b0f3` |
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
| _(floor: empty program)_ | _1.709_ | _1.758_ | _1.921_ | _23.139_ | _17.419_ |
| `lcg` | 39.439 | **39.426** | 39.745 | 2048.006 | 5239.598 |
| `packet_classifier` | **56.538** | 56.668 | 56.792 | 162.170 | 4423.564 |
| `ring_write` | **42.530** | 42.638 | 42.729 | 66.504 | 6117.700 |
| `histogram_bins` | **39.722** | 41.515 | 40.038 | 66.860 | 5875.300 |
| `prefix_scan` | **21.971** | 22.000 | 22.078 | 65.830 | 4502.652 |
| `binary_search` | **36.506** | 38.575 | 43.620 | 106.706 | 6016.247 |
| `sort_window` | **26.974** | 27.604 | 27.097 | 198.165 | 11657.205 |
| `bloom_filter` | **18.092** | 18.250 | 18.564 | 2845.101 | 7528.661 |
| `hash_join` | **27.148** | 30.277 | 29.924 | 3449.448 | 8249.727 |
| `sieve` | 18.435 | **18.029** | 18.266 | 65.095 | 3358.687 |
| `fib` | **25.371** | 30.126 | 28.273 | 129.884 | 1363.283 |
| `collatz` | **12.445** | 12.479 | 12.597 | 48.450 | 715.771 |
| `matmul` | 33.699 | **33.582** | 33.765 | 75.029 | 3115.377 |
| `json_parse` | 9.092 | **8.859** | 11.767 | 34.859 | 36.961 |
| `nbody` | **25.355** | 40.933 | 39.114 | 99.724 | 3013.555 |

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
| _(floor: empty program)_ | _2.920_ | _95.159_ | _**98.079**_ | _59.253_ | _59.046_ | _61.336_ |
| `lcg` | 3.012 | 95.819 | **98.831** | 59.148 | 68.117 | 68.526 |
| `packet_classifier` | 3.129 | 95.915 | **99.044** | 59.297 | 69.328 | 68.779 |
| `ring_write` | 3.226 | 97.503 | **100.729** | 59.017 | 70.391 | 70.029 |
| `histogram_bins` | 3.322 | 115.497 | **118.819** | 59.526 | 72.289 | 72.896 |
| `prefix_scan` | 3.366 | 101.317 | **104.683** | 59.790 | 74.735 | 72.200 |
| `binary_search` | 3.500 | 104.494 | **107.994** | 59.858 | 71.186 | 74.354 |
| `sort_window` | 3.519 | 107.257 | **110.776** | 59.146 | 77.149 | 79.164 |
| `bloom_filter` | 3.732 | 101.778 | **105.510** | 58.660 | 76.960 | 74.880 |
| `hash_join` | 6.220 | 254.128 | **260.348** | 61.174 | 120.157 | 111.411 |
| `sieve` | 3.340 | 99.029 | **102.369** | 58.188 | 78.980 | 78.493 |
| `fib` | 3.053 | 94.213 | **97.266** | 57.764 | 66.308 | 67.063 |
| `collatz` | 3.309 | 98.522 | **101.831** | 58.671 | 68.470 | 69.253 |
| `matmul` | 3.634 | 99.639 | **103.273** | 58.243 | 80.862 | 93.186 |
| `json_parse` | 52.580 | 429.458 | **482.038** | 108.647 | 123.349 | 178.144 |
| `nbody` | 4.909 | 123.163 | **128.072** | 59.721 | 95.740 | 91.531 |

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
