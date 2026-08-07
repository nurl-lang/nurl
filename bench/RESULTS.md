# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T08:16:59Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `335a9e45465f0a44484c91787818e5049797aeef` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31160734625 |
| NURL | `v0.34.0-16-g335a9e45` |
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
| _(floor: empty program)_ | _1.824_ | _1.854_ | _2.060_ | _26.071_ | _18.644_ |
| `lcg` | **44.348** | 44.409 | 44.623 | 1850.421 | 5386.264 |
| `packet_classifier` | **63.769** | 63.781 | 63.957 | 158.782 | 4798.295 |
| `ring_write` | 48.097 | **48.055** | 48.227 | 74.130 | 6637.463 |
| `histogram_bins` | **44.863** | 45.065 | 45.196 | 75.934 | 6532.168 |
| `prefix_scan` | **24.640** | 24.731 | 24.851 | 72.400 | 4770.936 |
| `binary_search` | **35.912** | 35.954 | 46.226 | 112.627 | 7206.165 |
| `sort_window` | 31.199 | 31.245 | **30.633** | 169.728 | 11093.684 |
| `bloom_filter` | **19.968** | 20.587 | 21.005 | 2765.714 | 7840.384 |
| `hash_join` | **29.661** | 31.242 | 31.524 | 3430.224 | 8361.887 |
| `sieve` | 20.889 | **20.262** | 20.338 | 72.605 | 3655.697 |
| `fib` | **28.221** | 33.669 | 29.766 | 142.552 | 1297.177 |
| `collatz` | **13.920** | 13.996 | 14.051 | 51.389 | 784.252 |
| `matmul` | **45.265** | 45.824 | 45.853 | 83.651 | 3634.765 |
| `json_parse` | **8.730** | 9.092 | 12.589 | 38.272 | 39.160 |
| `nbody` | 46.441 | 46.452 | **44.226** | 96.889 | 3208.527 |

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
| _(floor: empty program)_ | _2.998_ | _94.976_ | _**97.974**_ | _67.039_ | _68.552_ |
| `lcg` | 3.154 | 98.971 | **102.125** | 76.383 | 76.661 |
| `packet_classifier` | 3.150 | 98.857 | **102.007** | 76.379 | 76.120 |
| `ring_write` | 3.298 | 101.077 | **104.375** | 77.652 | 77.605 |
| `histogram_bins` | 3.249 | 101.686 | **104.935** | 79.260 | 79.371 |
| `prefix_scan` | 3.415 | 105.688 | **109.103** | 81.391 | 78.930 |
| `binary_search` | 3.451 | 104.297 | **107.748** | 78.041 | 83.826 |
| `sort_window` | 3.562 | 110.914 | **114.476** | 84.555 | 87.975 |
| `bloom_filter` | 3.694 | 109.460 | **113.154** | 84.331 | 85.332 |
| `hash_join` | 5.913 | 215.462 | **221.375** | 126.109 | 119.606 |
| `sieve` | 3.441 | 108.170 | **111.611** | 85.773 | 86.976 |
| `fib` | 3.085 | 97.953 | **101.038** | 76.309 | 77.244 |
| `collatz` | 3.244 | 98.559 | **101.803** | 74.271 | 75.795 |
| `matmul` | 3.578 | 104.341 | **107.919** | 84.731 | 98.055 |
| `json_parse` | 39.790 | 496.668 | **536.458** | 125.877 | 190.817 |
| `nbody` | 4.653 | 118.385 | **123.038** | 101.227 | 100.130 |

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
