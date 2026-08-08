# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T14:37:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `50cc2f3d3f04a1adabfacff4f3a00a9d04370f7e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31262219496 |
| NURL | `v0.35.1-38-g50cc2f3d` |
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
| _(floor: empty program)_ | _1.623_ | _1.696_ | _1.870_ | _23.883_ | _18.094_ |
| `lcg` | **39.200** | 39.323 | 39.422 | 1873.758 | 5150.370 |
| `packet_classifier` | **56.655** | 56.851 | 56.986 | 163.487 | 4496.726 |
| `ring_write` | **42.436** | 42.476 | 42.633 | 67.613 | 6271.804 |
| `histogram_bins` | **39.680** | 41.378 | 39.846 | 66.610 | 6101.726 |
| `prefix_scan` | 22.171 | 22.110 | **22.073** | 66.870 | 4541.360 |
| `binary_search` | 40.053 | **38.491** | 43.549 | 106.701 | 5987.174 |
| `sort_window` | 27.403 | 27.572 | **27.072** | 198.798 | 11341.078 |
| `bloom_filter` | **18.413** | 19.141 | 19.042 | 2837.751 | 7406.674 |
| `hash_join` | **28.217** | 30.376 | 30.233 | 3435.784 | 8162.160 |
| `sieve` | 21.303 | 18.815 | **18.694** | 67.291 | 3279.019 |
| `fib` | **25.375** | 30.252 | 28.625 | 132.194 | 1369.266 |
| `collatz` | **12.618** | 12.840 | 12.820 | 52.020 | 714.704 |
| `matmul` | **33.894** | 33.964 | 34.198 | 78.217 | 3100.519 |
| `json_parse` | 42.598 | **9.064** | 12.193 | 37.404 | 41.202 |
| `nbody` | 41.145 | 41.304 | **39.347** | 101.359 | 3053.110 |

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
| _(floor: empty program)_ | _2.672_ | _81.880_ | _**84.552**_ | _59.227_ | _60.493_ |
| `lcg` | 2.846 | 89.262 | **92.108** | 68.451 | 68.078 |
| `packet_classifier` | 2.827 | 90.272 | **93.099** | 67.750 | 68.097 |
| `ring_write` | 2.985 | 88.290 | **91.275** | 69.527 | 70.147 |
| `histogram_bins` | 3.143 | 93.089 | **96.232** | 71.266 | 72.771 |
| `prefix_scan` | 3.209 | 95.958 | **99.167** | 74.296 | 71.701 |
| `binary_search` | 3.167 | 93.682 | **96.849** | 70.873 | 83.103 |
| `sort_window` | 3.295 | 99.957 | **103.252** | 77.247 | 78.635 |
| `bloom_filter` | 3.401 | 101.243 | **104.644** | 77.658 | 74.923 |
| `hash_join` | 5.623 | 218.013 | **223.636** | 121.337 | 112.829 |
| `sieve` | 3.123 | 98.477 | **101.600** | 80.591 | 81.410 |
| `fib` | 2.850 | 89.685 | **92.535** | 70.078 | 69.230 |
| `collatz` | 3.071 | 94.013 | **97.084** | 71.082 | 72.837 |
| `matmul` | 3.314 | 100.578 | **103.892** | 83.271 | 97.294 |
| `json_parse` | 42.964 | 560.179 | **603.143** | 129.947 | 182.115 |
| `nbody` | 4.561 | 113.157 | **117.718** | 101.668 | 98.129 |

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
