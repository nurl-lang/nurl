# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-26T20:34:44Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d127ed8c699807f512950a769695a997615dfc7c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30219089921 |
| NURL | `v0.25.1-13-gd127ed8` |
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
| _(floor: empty program)_ | _1.653_ | _1.711_ | _1.812_ | _22.313_ | _17.136_ |
| `lcg` | **3.676** | 17.443 | 17.522 | 6370.608 | 16095.002 |
| `affine_mix` | **14.257** | 18.948 | 19.114 | 1433.344 | 5007.536 |
| `packet_classifier` | **56.304** | 56.429 | 56.566 | 162.515 | 4230.244 |
| `ring_write` | 33.123 | **32.952** | 33.213 | 53.783 | 4749.482 |
| `histogram_bins` | **27.400** | 27.621 | 27.476 | 56.605 | 4334.307 |
| `prefix_scan` | **21.880** | 21.918 | 22.016 | 64.559 | 4705.805 |
| `binary_search` | 39.819 | **38.369** | 43.388 | 106.343 | 6151.715 |
| `sort_window` | 27.363 | 64.004 | **26.882** | 196.672 | 11159.159 |
| `bloom_filter` | **18.107** | 18.281 | 18.513 | 2865.845 | 7625.766 |
| `hash_join` | **4.480** | 4.699 | 4.845 | 371.732 | 844.861 |
| `sieve` | 18.544 | **17.901** | 17.958 | 64.660 | 3213.376 |
| `fib` | **25.176** | 29.951 | 28.216 | 130.777 | 1373.765 |
| `collatz` | **12.455** | 12.464 | 12.476 | 49.380 | 716.087 |
| `matmul` | **33.642** | 33.645 | 33.843 | 76.513 | 3309.771 |
| `json_parse` | 10.664 | **2.885** | 11.673 | 37.802 | 37.420 |

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
| _(floor: empty program)_ | _2.958_ | _80.015_ | _**82.973**_ | _57.088_ | _61.852_ |
| `lcg` | 2.961 | 83.468 | **86.429** | 64.388 | 66.302 |
| `affine_mix` | 3.115 | 88.810 | **91.925** | 70.674 | 69.550 |
| `packet_classifier` | 3.150 | 85.393 | **88.543** | 67.734 | 67.608 |
| `ring_write` | 3.331 | 86.862 | **90.193** | 68.237 | 67.623 |
| `histogram_bins` | 3.437 | 91.302 | **94.739** | 70.547 | 72.859 |
| `prefix_scan` | 3.535 | 90.426 | **93.961** | 73.044 | 72.177 |
| `binary_search` | 3.822 | 89.511 | **93.333** | 69.473 | 72.872 |
| `sort_window` | 3.853 | 97.619 | **101.472** | 74.342 | 80.981 |
| `bloom_filter` | 4.063 | 94.496 | **98.559** | 75.782 | 75.547 |
| `hash_join` | 8.485 | 209.650 | **218.135** | 119.657 | 108.770 |
| `sieve` | 3.466 | 91.392 | **94.858** | 78.323 | 78.527 |
| `fib` | 3.004 | 83.771 | **86.775** | 66.312 | 67.558 |
| `collatz` | 3.311 | 90.229 | **93.540** | 66.862 | 69.411 |
| `matmul` | 4.392 | 95.207 | **99.599** | 82.343 | 91.206 |
| `json_parse` | 69.290 | 723.132 | **792.422** | 104.583 | 177.147 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
line. A speed number for a program computing something else is worthless,
so a mismatch drops the row out of the tables above rather than being
reported as a fast cell.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `6299863613973285121` | identical across 5 languages |
| `affine_mix` | `23394348946257561` | identical across 5 languages |
| `packet_classifier` | `4205972061` | identical across 5 languages |
| `ring_write` | `3856155665848586533` | identical across 5 languages |
| `histogram_bins` | `3775845141` | identical across 5 languages |
| `prefix_scan` | `492982549` | identical across 5 languages |
| `binary_search` | `805907445` | identical across 5 languages |
| `sort_window` | `2815490238` | identical across 5 languages |
| `bloom_filter` | `2351703` | identical across 5 languages |
| `hash_join` | `2814341850483607168` | identical across 5 languages |
| `sieve` | `664579` | identical across 5 languages |
| `fib` | `9227465` | identical across 5 languages |
| `collatz` | `350` | identical across 5 languages |
| `matmul` | `393199` | identical across 5 languages |
| `json_parse` | `20` | identical across 5 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Ten of the fifteen benchmarks are defined over 64-bit unsigned integers.
  Python has arbitrary-precision integers and masks; JS has no 64-bit
  integer at all, so those rows use `BigInt` where the algorithm genuinely
  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each
  file says which and why. That gap *is* part of what this table reports.
* `json_parse` is the one row whose gate is "every parser accepted the
  document" rather than a structural checksum: each language uses the
  parser in its own box (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`), and C and Rust — whose boxes are empty — carry a
  small hand-written recursive-descent parser in the benchmark file.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
