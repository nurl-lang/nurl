# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T22:53:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377688 KiB |
| Commit | `5379a42e84e19749eaf0147f320fe2d2ebe853d6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31543982035 |
| NURL | `v0.38.0-18-g5379a42e` |
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
| _(floor: empty program)_ | _1.654_ | _1.709_ | _1.830_ | _23.150_ | _17.237_ |
| `lcg` | **39.322** | 39.460 | 39.486 | 1876.645 | 5494.844 |
| `packet_classifier` | **56.554** | 56.708 | 56.733 | 165.171 | 4482.259 |
| `ring_write` | **42.465** | 42.475 | 42.622 | 66.359 | 6493.432 |
| `histogram_bins` | **39.804** | 41.520 | 40.091 | 68.804 | 5942.171 |
| `prefix_scan` | 21.935 | **21.899** | 22.106 | 65.995 | 4476.815 |
| `binary_search` | 39.833 | **38.557** | 43.519 | 106.707 | 6283.559 |
| `sort_window` | 27.364 | 27.498 | **26.988** | 197.196 | 11905.046 |
| `bloom_filter` | **18.207** | 18.373 | 18.560 | 2823.720 | 7647.584 |
| `hash_join` | **28.078** | 30.153 | 30.243 | 3411.257 | 8172.455 |
| `sieve` | **18.411** | 18.650 | 18.919 | 66.672 | 3709.141 |
| `fib` | **25.425** | 30.106 | 28.278 | 132.385 | 1342.304 |
| `collatz` | **12.416** | 12.543 | 12.601 | 52.363 | 714.281 |
| `matmul` | 33.809 | **33.752** | 33.819 | 77.726 | 3014.033 |
| `json_parse` | 8.914 | **8.887** | 11.804 | 36.578 | 38.906 |
| `nbody` | 41.035 | 40.953 | **39.183** | 102.335 | 3065.573 |

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
| _(floor: empty program)_ | _2.912_ | _82.298_ | _**85.210**_ | _57.458_ | _60.989_ |
| `lcg` | 2.821 | 86.680 | **89.501** | 67.568 | 67.677 |
| `packet_classifier` | 2.936 | 90.031 | **92.967** | 69.931 | 68.581 |
| `ring_write` | 2.973 | 89.437 | **92.410** | 68.895 | 70.570 |
| `histogram_bins` | 3.079 | 95.835 | **98.914** | 71.579 | 73.601 |
| `prefix_scan` | 3.159 | 93.720 | **96.879** | 73.494 | 72.698 |
| `binary_search` | 3.356 | 94.732 | **98.088** | 71.941 | 75.620 |
| `sort_window` | 3.334 | 99.213 | **102.547** | 78.054 | 77.742 |
| `bloom_filter` | 3.485 | 97.638 | **101.123** | 76.703 | 80.428 |
| `hash_join` | 5.667 | 212.372 | **218.039** | 120.222 | 110.903 |
| `sieve` | 3.141 | 92.349 | **95.490** | 79.606 | 78.122 |
| `fib` | 2.865 | 86.303 | **89.168** | 68.948 | 66.660 |
| `collatz` | 3.120 | 91.251 | **94.371** | 69.368 | 70.854 |
| `matmul` | 3.411 | 99.742 | **103.153** | 82.410 | 94.173 |
| `json_parse` | 44.621 | 544.712 | **589.333** | 126.238 | 180.719 |
| `nbody` | 4.591 | 110.670 | **115.261** | 98.724 | 97.257 |

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
