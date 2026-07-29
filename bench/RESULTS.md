# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-29T10:30:37Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `7a260e6b5ddae35e598460377cf514f62a1a4d80` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30443616570 |
| NURL | `v0.27.0-58-g7a260e6` |
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
| _(floor: empty program)_ | _1.648_ | _1.709_ | _1.844_ | _24.256_ | _17.628_ |
| `lcg` | 39.544 | **39.517** | 39.595 | 1882.037 | 5173.567 |
| `packet_classifier` | 56.661 | **56.626** | 56.825 | 163.153 | 4438.945 |
| `ring_write` | **42.624** | 42.704 | 42.894 | 66.564 | 6309.727 |
| `histogram_bins` | **39.862** | 41.526 | 40.053 | 68.522 | 6251.403 |
| `prefix_scan` | **22.207** | 22.258 | 22.319 | 66.156 | 4543.674 |
| `binary_search` | 40.106 | **38.642** | 43.644 | 108.251 | 6004.883 |
| `sort_window` | 27.649 | 27.688 | **27.151** | 198.088 | 11401.971 |
| `bloom_filter` | **18.096** | 18.454 | 18.551 | 2816.083 | 7540.810 |
| `hash_join` | **28.348** | 30.358 | 30.166 | 3409.716 | 8315.922 |
| `sieve` | 21.374 | 21.130 | **21.117** | 67.574 | 3216.943 |
| `fib` | **25.530** | 30.240 | 28.555 | 132.032 | 1343.678 |
| `collatz` | **12.522** | 12.564 | 12.872 | 51.678 | 708.236 |
| `matmul` | 33.934 | 34.163 | **33.910** | 78.035 | 3351.044 |
| `json_parse` | **8.588** | 8.891 | 11.827 | 37.787 | 39.157 |
| `nbody` | 41.262 | 41.273 | **39.381** | 104.114 | 3254.998 |

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
| _(floor: empty program)_ | _2.871_ | _80.474_ | _**83.345**_ | _57.912_ | _61.290_ |
| `lcg` | 3.223 | 88.222 | **91.445** | 69.103 | 71.993 |
| `packet_classifier` | 3.238 | 89.957 | **93.195** | 70.430 | 71.269 |
| `ring_write` | 3.373 | 91.500 | **94.873** | 70.898 | 73.326 |
| `histogram_bins` | 3.567 | 95.025 | **98.592** | 72.442 | 74.031 |
| `prefix_scan` | 3.653 | 95.394 | **99.047** | 75.227 | 75.082 |
| `binary_search` | 3.946 | 94.707 | **98.653** | 70.663 | 76.493 |
| `sort_window` | 4.086 | 101.386 | **105.472** | 78.881 | 83.669 |
| `bloom_filter` | 4.122 | 96.005 | **100.127** | 77.164 | 78.171 |
| `hash_join` | 8.838 | 209.893 | **218.731** | 119.597 | 110.112 |
| `sieve` | 3.562 | 91.701 | **95.263** | 78.367 | 79.221 |
| `fib` | 3.043 | 85.300 | **88.343** | 67.149 | 68.693 |
| `collatz` | 3.350 | 89.793 | **93.143** | 69.530 | 70.255 |
| `matmul` | 4.472 | 97.426 | **101.898** | 80.974 | 92.643 |
| `json_parse` | 73.302 | 732.187 | **805.489** | 126.426 | 181.169 |
| `nbody` | 7.438 | 109.092 | **116.530** | 99.034 | 97.548 |

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
