# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-12T19:15:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `002cba31cb72fd4e21a7be900d4e08072a95d0da` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31631321021 |
| NURL | `v0.39.0-18-g002cba31` |
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
| _(floor: empty program)_ | _1.826_ | _1.886_ | _2.042_ | _24.205_ | _18.265_ |
| `lcg` | **44.330** | 44.530 | 44.546 | 1833.338 | 5272.588 |
| `packet_classifier` | **63.699** | 63.763 | 63.943 | 159.044 | 4556.096 |
| `ring_write` | 47.954 | **47.903** | 48.112 | 73.682 | 6925.507 |
| `histogram_bins` | **44.709** | 44.937 | 45.101 | 75.928 | 6452.101 |
| `prefix_scan` | **24.809** | 24.847 | 25.047 | 72.414 | 5140.014 |
| `binary_search` | **36.059** | 36.182 | 46.356 | 112.104 | 6448.895 |
| `sort_window` | 31.034 | 31.097 | **30.631** | 169.444 | 11558.200 |
| `bloom_filter` | **20.019** | 20.651 | 21.093 | 2755.357 | 7578.068 |
| `hash_join` | **29.488** | 31.206 | 31.473 | 3391.261 | 8266.390 |
| `sieve` | 21.096 | **20.917** | 20.962 | 73.503 | 3375.440 |
| `fib` | **28.292** | 33.629 | 29.827 | 143.456 | 1287.125 |
| `collatz` | **13.981** | 14.115 | 14.241 | 54.652 | 753.244 |
| `matmul` | **45.995** | 46.979 | 46.612 | 83.462 | 3373.034 |
| `json_parse` | **8.774** | 9.116 | 12.405 | 39.968 | 38.770 |
| `nbody` | 46.484 | 46.603 | **44.400** | 96.286 | 3208.352 |

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
| _(floor: empty program)_ | _3.188_ | _90.153_ | _**93.341**_ | _67.921_ | _66.161_ |
| `lcg` | 3.235 | 96.656 | **99.891** | 76.316 | 74.703 |
| `packet_classifier` | 3.248 | 98.034 | **101.282** | 75.885 | 74.543 |
| `ring_write` | 3.406 | 99.796 | **103.202** | 76.246 | 80.214 |
| `histogram_bins` | 3.438 | 103.658 | **107.096** | 79.603 | 79.364 |
| `prefix_scan` | 3.478 | 105.540 | **109.018** | 82.010 | 78.500 |
| `binary_search` | 3.652 | 104.945 | **108.597** | 79.634 | 83.401 |
| `sort_window` | 3.790 | 112.347 | **116.137** | 85.996 | 87.816 |
| `bloom_filter` | 3.918 | 112.684 | **116.602** | 85.507 | 82.949 |
| `hash_join` | 6.140 | 215.138 | **221.278** | 126.216 | 117.814 |
| `sieve` | 3.654 | 108.300 | **111.954** | 89.045 | 88.234 |
| `fib` | 3.292 | 99.943 | **103.235** | 78.525 | 74.244 |
| `collatz` | 3.458 | 103.789 | **107.247** | 79.065 | 79.567 |
| `matmul` | 3.729 | 111.341 | **115.070** | 91.669 | 101.705 |
| `json_parse` | 43.474 | 520.756 | **564.230** | 127.538 | 187.317 |
| `nbody` | 4.826 | 116.991 | **121.817** | 101.221 | 100.812 |

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
