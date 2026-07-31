# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T19:55:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `236bda680c2523de71b3da2d6d5bac5533304993` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30660605689 |
| NURL | `v0.29.0-99-g236bda6` |
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
| _(floor: empty program)_ | _1.665_ | _1.743_ | _1.867_ | _23.396_ | _17.129_ |
| `lcg` | 39.295 | **39.263** | 39.291 | 1882.523 | 5066.093 |
| `packet_classifier` | 56.607 | **56.474** | 56.653 | 161.761 | 4392.159 |
| `ring_write` | 42.610 | **42.490** | 42.632 | 67.409 | 6281.728 |
| `histogram_bins` | **39.781** | 41.427 | 40.666 | 67.486 | 5973.098 |
| `prefix_scan` | **21.973** | 21.999 | 22.104 | 65.785 | 4546.534 |
| `binary_search` | 39.950 | **38.636** | 43.278 | 107.350 | 6068.319 |
| `sort_window` | 27.551 | 27.495 | **27.033** | 199.084 | 11690.799 |
| `bloom_filter` | **17.970** | 18.284 | 18.635 | 2833.054 | 8390.271 |
| `hash_join` | **28.094** | 30.088 | 30.108 | 3416.329 | 8304.283 |
| `sieve` | 21.101 | 20.411 | **20.379** | 68.178 | 3245.667 |
| `fib` | **25.283** | 30.033 | 28.365 | 131.888 | 1341.758 |
| `collatz` | 12.945 | 12.921 | **12.740** | 52.084 | 717.483 |
| `matmul` | **33.707** | 33.804 | 34.151 | 80.293 | 3071.658 |
| `json_parse` | **8.659** | 9.019 | 11.853 | 37.281 | 38.044 |
| `nbody` | 41.124 | 41.025 | **39.117** | 101.772 | 3048.985 |

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
| _(floor: empty program)_ | _2.656_ | _80.525_ | _**83.181**_ | _60.854_ | _66.583_ |
| `lcg` | 2.887 | 84.526 | **87.413** | 67.324 | 71.018 |
| `packet_classifier` | 2.942 | 88.715 | **91.657** | 69.178 | 70.769 |
| `ring_write` | 3.012 | 87.641 | **90.653** | 70.673 | 77.068 |
| `histogram_bins` | 3.108 | 91.090 | **94.198** | 72.178 | 73.240 |
| `prefix_scan` | 3.159 | 92.365 | **95.524** | 74.562 | 74.217 |
| `binary_search` | 3.505 | 90.971 | **94.476** | 72.267 | 77.714 |
| `sort_window` | 3.460 | 99.742 | **103.202** | 79.735 | 81.776 |
| `bloom_filter` | 3.754 | 102.175 | **105.929** | 78.076 | 78.523 |
| `hash_join` | 6.975 | 213.451 | **220.426** | 120.827 | 111.808 |
| `sieve` | 3.387 | 96.329 | **99.716** | 80.182 | 81.848 |
| `fib` | 2.834 | 86.407 | **89.241** | 68.598 | 68.125 |
| `collatz` | 3.160 | 93.118 | **96.278** | 73.392 | 74.259 |
| `matmul` | 3.563 | 100.557 | **104.120** | 83.132 | 95.252 |
| `json_parse` | 54.705 | 525.709 | **580.414** | 125.829 | 197.141 |
| `nbody` | 5.163 | 109.630 | **114.793** | 99.728 | 94.388 |

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
