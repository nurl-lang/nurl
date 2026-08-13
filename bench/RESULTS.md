# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T05:27:12Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `b20dc82c6270202565773a2b01878a0db784a59c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31670097071 |
| NURL | `v0.39.0-28-gb20dc82c` |
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
| _(floor: empty program)_ | _1.731_ | _1.718_ | _1.862_ | _24.154_ | _17.496_ |
| `lcg` | **39.488** | 39.522 | 39.677 | 1872.941 | 5171.542 |
| `packet_classifier` | **56.589** | 56.778 | 56.774 | 162.550 | 4346.981 |
| `ring_write` | **42.474** | 42.669 | 42.822 | 65.994 | 6327.208 |
| `histogram_bins` | **39.819** | 41.677 | 40.145 | 66.999 | 6146.858 |
| `prefix_scan` | **22.081** | 22.145 | 22.190 | 66.093 | 4677.912 |
| `binary_search` | 40.113 | **38.653** | 43.698 | 108.488 | 6117.100 |
| `sort_window` | 27.490 | 27.872 | **27.109** | 199.018 | 12911.105 |
| `bloom_filter` | **18.115** | 18.384 | 18.700 | 3033.550 | 7499.401 |
| `hash_join` | **28.286** | 30.537 | 30.365 | 3414.834 | 8711.473 |
| `sieve` | 19.173 | **18.456** | 18.607 | 67.915 | 3337.385 |
| `fib` | **25.322** | 30.210 | 28.388 | 133.488 | 1340.758 |
| `collatz` | 12.565 | **12.547** | 12.631 | 50.190 | 709.118 |
| `matmul` | 33.970 | **33.820** | 33.977 | 76.925 | 3258.090 |
| `json_parse` | 9.129 | **9.030** | 12.159 | 37.705 | 39.017 |
| `nbody` | 41.115 | 41.163 | **39.220** | 103.143 | 3061.570 |

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
| _(floor: empty program)_ | _2.845_ | _82.598_ | _**85.443**_ | _58.679_ | _66.856_ |
| `lcg` | 2.924 | 87.637 | **90.561** | 68.624 | 71.165 |
| `packet_classifier` | 2.999 | 89.946 | **92.945** | 68.978 | 71.003 |
| `ring_write` | 3.085 | 90.736 | **93.821** | 72.479 | 73.399 |
| `histogram_bins` | 3.100 | 96.160 | **99.260** | 72.409 | 75.324 |
| `prefix_scan` | 3.295 | 100.720 | **104.015** | 75.758 | 74.487 |
| `binary_search` | 3.255 | 94.498 | **97.753** | 71.063 | 77.336 |
| `sort_window` | 3.441 | 101.438 | **104.879** | 77.863 | 80.410 |
| `bloom_filter` | 3.516 | 100.852 | **104.368** | 79.439 | 77.896 |
| `hash_join` | 5.620 | 215.794 | **221.414** | 122.058 | 116.706 |
| `sieve` | 3.179 | 95.810 | **98.989** | 81.028 | 82.576 |
| `fib` | 3.002 | 88.429 | **91.431** | 68.681 | 70.660 |
| `collatz` | 3.124 | 92.884 | **96.008** | 71.354 | 71.753 |
| `matmul` | 3.389 | 101.755 | **105.144** | 83.158 | 99.120 |
| `json_parse` | 44.206 | 547.521 | **591.727** | 125.778 | 188.189 |
| `nbody` | 4.665 | 110.253 | **114.918** | 97.010 | 97.465 |

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
