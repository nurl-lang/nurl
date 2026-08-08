# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T15:02:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `56a86d7c1ea9810be61bd56eb59856c6fbfb7f55` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31263232019 |
| NURL | `v0.35.1-41-g56a86d7c` |
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
| _(floor: empty program)_ | _1.802_ | _1.915_ | _2.035_ | _24.846_ | _18.395_ |
| `lcg` | **44.361** | 44.482 | 44.597 | 1837.446 | 6363.160 |
| `packet_classifier` | **63.887** | 63.896 | 64.084 | 156.725 | 4531.883 |
| `ring_write` | **47.907** | 48.030 | 48.154 | 73.255 | 7288.812 |
| `histogram_bins` | **44.900** | 44.973 | 45.122 | 75.867 | 6427.970 |
| `prefix_scan` | **24.735** | 24.773 | 24.903 | 73.025 | 4999.670 |
| `binary_search` | **35.843** | 36.169 | 46.365 | 110.741 | 6716.252 |
| `sort_window` | 30.990 | 31.139 | **30.494** | 165.571 | 11637.416 |
| `bloom_filter` | **20.128** | 20.784 | 21.099 | 2805.264 | 7825.557 |
| `hash_join` | **29.475** | 31.119 | 31.543 | 3401.278 | 8171.442 |
| `sieve` | 21.018 | **20.735** | 20.831 | 71.644 | 3332.486 |
| `fib` | **28.302** | 33.676 | 29.674 | 143.412 | 1298.868 |
| `collatz` | **14.061** | 14.102 | 14.254 | 54.308 | 752.149 |
| `matmul` | **45.664** | 46.251 | 46.399 | 85.603 | 3433.041 |
| `json_parse` | 46.050 | **9.147** | 12.506 | 39.433 | 39.484 |
| `nbody` | 46.541 | 46.464 | **44.407** | 97.184 | 3172.305 |

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
| _(floor: empty program)_ | _3.033_ | _91.556_ | _**94.589**_ | _66.021_ | _112.136_ |
| `lcg` | 3.145 | 95.799 | **98.944** | 73.725 | 74.228 |
| `packet_classifier` | 3.276 | 98.453 | **101.729** | 76.885 | 75.609 |
| `ring_write` | 3.314 | 101.884 | **105.198** | 77.917 | 75.583 |
| `histogram_bins` | 3.389 | 101.371 | **104.760** | 78.504 | 77.513 |
| `prefix_scan` | 3.350 | 103.203 | **106.553** | 80.373 | 78.147 |
| `binary_search` | 3.475 | 103.038 | **106.513** | 77.120 | 81.096 |
| `sort_window` | 3.603 | 108.817 | **112.420** | 83.296 | 85.960 |
| `bloom_filter` | 3.761 | 107.596 | **111.357** | 84.681 | 81.574 |
| `hash_join` | 5.960 | 218.154 | **224.114** | 126.852 | 118.097 |
| `sieve` | 3.431 | 106.007 | **109.438** | 87.001 | 87.022 |
| `fib` | 3.135 | 98.548 | **101.683** | 76.768 | 75.274 |
| `collatz` | 3.391 | 103.021 | **106.412** | 79.015 | 79.099 |
| `matmul` | 3.591 | 109.948 | **113.539** | 88.586 | 101.595 |
| `json_parse` | 41.102 | 530.355 | **571.457** | 127.586 | 191.197 |
| `nbody` | 4.695 | 120.637 | **125.332** | 103.677 | 102.331 |

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
