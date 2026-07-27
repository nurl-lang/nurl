# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-27T00:01:57Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `fe2fc2930dd5be1d26f31f133acbd1473de8bfb5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30226327087 |
| NURL | `v0.26.0-9-gfe2fc29` |
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
| _(floor: empty program)_ | _1.823_ | _1.892_ | _2.037_ | _23.735_ | _17.978_ |
| `lcg` | **44.335** | 44.418 | 44.460 | 1830.374 | 5312.733 |
| `affine_mix` | **44.259** | 44.282 | 44.451 | 1973.290 | 6908.215 |
| `packet_classifier` | **63.663** | 63.734 | 63.805 | 158.095 | 4547.941 |
| `ring_write` | **47.705** | 47.900 | 47.944 | 73.551 | 6776.094 |
| `histogram_bins` | **44.681** | 44.831 | 44.885 | 73.672 | 6583.074 |
| `prefix_scan` | **24.603** | 24.625 | 24.827 | 72.301 | 4836.111 |
| `binary_search` | **35.775** | 35.882 | 46.168 | 112.634 | 6335.974 |
| `sort_window` | 30.867 | 30.967 | **30.411** | 166.669 | 10961.994 |
| `bloom_filter` | **19.875** | 20.519 | 20.813 | 2854.865 | 7651.877 |
| `hash_join` | **4.805** | 5.017 | 5.170 | 379.264 | 844.308 |
| `sieve` | 21.150 | **20.566** | 20.692 | 73.394 | 3519.017 |
| `fib` | **28.067** | 33.511 | 29.544 | 142.825 | 1289.511 |
| `collatz` | 13.975 | **13.956** | 14.102 | 53.751 | 757.770 |
| `matmul` | **45.568** | 46.014 | 46.057 | 83.183 | 3689.580 |
| `json_parse` | **8.444** | 9.184 | 12.335 | 40.028 | 38.284 |

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
| _(floor: empty program)_ | _3.268_ | _90.225_ | _**93.493**_ | _66.324_ | _70.262_ |
| `lcg` | 3.448 | 92.811 | **96.259** | 72.289 | 74.794 |
| `affine_mix` | 3.513 | 96.207 | **99.720** | 73.659 | 73.628 |
| `packet_classifier` | 3.517 | 93.427 | **96.944** | 73.460 | 74.855 |
| `ring_write` | 3.706 | 94.783 | **98.489** | 74.072 | 75.807 |
| `histogram_bins` | 3.916 | 99.018 | **102.934** | 75.960 | 79.062 |
| `prefix_scan` | 3.986 | 99.594 | **103.580** | 78.311 | 77.743 |
| `binary_search` | 4.266 | 97.390 | **101.656** | 75.280 | 79.039 |
| `sort_window` | 4.340 | 105.674 | **110.014** | 83.154 | 84.856 |
| `bloom_filter` | 4.598 | 105.268 | **109.866** | 82.368 | 80.609 |
| `hash_join` | 9.654 | 211.614 | **221.268** | 123.544 | 117.498 |
| `sieve` | 4.005 | 103.630 | **107.635** | 86.575 | 91.109 |
| `fib` | 3.405 | 93.085 | **96.490** | 73.838 | 73.078 |
| `collatz` | 3.853 | 100.229 | **104.082** | 74.834 | 76.485 |
| `matmul` | 4.917 | 106.126 | **111.043** | 88.232 | 99.661 |
| `json_parse` | 77.600 | 695.341 | **772.941** | 127.505 | 188.657 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
line. A speed number for a program computing something else is worthless,
so a mismatch drops the row out of the tables above rather than being
reported as a fast cell.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical across 5 languages |
| `affine_mix` | `227901546981696845` | identical across 5 languages |
| `packet_classifier` | `4205972061` | identical across 5 languages |
| `ring_write` | `8299504528805184357` | identical across 5 languages |
| `histogram_bins` | `1215643728` | identical across 5 languages |
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
