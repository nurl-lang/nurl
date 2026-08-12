# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-12T15:23:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `df2f443039a919b7d9a469f3ef39a6676127f316` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31611602510 |
| NURL | `v0.39.0-9-gdf2f4430` |
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
| _(floor: empty program)_ | _1.637_ | _1.693_ | _1.825_ | _21.569_ | _16.988_ |
| `lcg` | **39.173** | 39.304 | 39.393 | 2047.285 | 5275.069 |
| `packet_classifier` | **56.403** | 56.676 | 56.772 | 161.650 | 4295.090 |
| `ring_write` | **42.306** | 42.379 | 42.534 | 65.964 | 6809.895 |
| `histogram_bins` | **39.602** | 41.403 | 39.853 | 66.074 | 5986.024 |
| `prefix_scan` | **21.892** | 21.932 | 22.024 | 64.116 | 4630.269 |
| `binary_search` | 39.828 | **38.494** | 43.413 | 105.846 | 6580.764 |
| `sort_window` | 27.406 | 27.558 | **27.062** | 198.640 | 11201.350 |
| `bloom_filter` | **18.017** | 18.273 | 18.522 | 2832.327 | 7993.879 |
| `hash_join` | **28.314** | 30.412 | 30.072 | 3413.104 | 8297.252 |
| `sieve` | 18.284 | **18.193** | 18.345 | 64.000 | 3301.455 |
| `fib` | **25.151** | 29.933 | 28.259 | 133.348 | 1381.806 |
| `collatz` | **12.448** | 12.463 | 12.549 | 50.931 | 731.604 |
| `matmul` | 33.876 | **33.870** | 33.912 | 76.667 | 3352.458 |
| `json_parse` | 8.940 | **8.843** | 11.739 | 35.603 | 37.178 |
| `nbody` | 40.987 | 41.101 | **39.254** | 100.957 | 3072.660 |

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
| _(floor: empty program)_ | _2.660_ | _78.000_ | _**80.660**_ | _56.264_ | _60.184_ |
| `lcg` | 2.774 | 88.014 | **90.788** | 64.614 | 66.427 |
| `packet_classifier` | 2.871 | 88.341 | **91.212** | 67.587 | 66.625 |
| `ring_write` | 3.044 | 92.908 | **95.952** | 71.678 | 71.253 |
| `histogram_bins` | 3.012 | 89.270 | **92.282** | 68.770 | 69.781 |
| `prefix_scan` | 3.087 | 90.937 | **94.024** | 70.692 | 70.164 |
| `binary_search` | 3.167 | 89.223 | **92.390** | 68.087 | 74.097 |
| `sort_window` | 3.221 | 97.128 | **100.349** | 73.779 | 78.772 |
| `bloom_filter` | 3.550 | 101.266 | **104.816** | 78.757 | 73.031 |
| `hash_join` | 5.595 | 207.313 | **212.908** | 118.936 | 107.973 |
| `sieve` | 3.077 | 91.451 | **94.528** | 77.119 | 81.606 |
| `fib` | 2.789 | 82.295 | **85.084** | 64.968 | 65.261 |
| `collatz` | 2.987 | 90.285 | **93.272** | 65.880 | 68.410 |
| `matmul` | 3.300 | 97.275 | **100.575** | 79.995 | 91.258 |
| `json_parse` | 43.919 | 540.731 | **584.650** | 126.256 | 177.139 |
| `nbody` | 4.461 | 108.656 | **113.117** | 96.127 | 92.568 |

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
