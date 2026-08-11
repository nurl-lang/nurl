# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T04:55:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1e815be9f9c8423cb8b3f149c7d92cf8a689d6eb` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31459749078 |
| NURL | `v0.36.0-101-g1e815be9` |
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
| _(floor: empty program)_ | _1.644_ | _1.735_ | _1.869_ | _23.843_ | _17.031_ |
| `lcg` | **39.242** | 39.344 | 39.408 | 1889.829 | 5190.693 |
| `packet_classifier` | **56.391** | 56.550 | 56.641 | 162.915 | 4415.945 |
| `ring_write` | **42.430** | 42.459 | 42.624 | 67.017 | 6278.384 |
| `histogram_bins` | **39.667** | 41.297 | 39.738 | 65.702 | 5950.337 |
| `prefix_scan` | **21.941** | 21.986 | 22.113 | 67.335 | 4441.392 |
| `binary_search` | 39.797 | **38.396** | 43.259 | 106.159 | 5900.274 |
| `sort_window` | 27.536 | 27.497 | **27.088** | 200.341 | 12803.652 |
| `bloom_filter` | **17.966** | 18.276 | 18.553 | 2818.914 | 7810.600 |
| `hash_join` | **27.970** | 30.248 | 29.959 | 3410.039 | 8304.467 |
| `sieve` | 20.391 | 20.453 | **19.931** | 65.605 | 3200.572 |
| `fib` | **25.244** | 29.994 | 28.369 | 132.292 | 1347.712 |
| `collatz` | **12.501** | 12.531 | 12.623 | 51.124 | 714.088 |
| `matmul` | **33.543** | 33.824 | 33.675 | 75.584 | 3284.113 |
| `json_parse` | 42.415 | **8.894** | 11.682 | 36.365 | 37.651 |
| `nbody` | 40.832 | 40.878 | **38.988** | 102.216 | 3027.215 |

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
| _(floor: empty program)_ | _2.766_ | _81.261_ | _**84.027**_ | _58.356_ | _61.000_ |
| `lcg` | 2.912 | 86.799 | **89.711** | 66.356 | 72.063 |
| `packet_classifier` | 2.951 | 86.113 | **89.064** | 67.001 | 66.782 |
| `ring_write` | 3.002 | 92.052 | **95.054** | 70.916 | 69.939 |
| `histogram_bins` | 3.047 | 91.568 | **94.615** | 69.866 | 72.271 |
| `prefix_scan` | 3.052 | 90.710 | **93.762** | 71.857 | 73.452 |
| `binary_search` | 3.288 | 90.057 | **93.345** | 68.548 | 75.623 |
| `sort_window` | 3.145 | 96.304 | **99.449** | 73.644 | 78.858 |
| `bloom_filter` | 3.439 | 95.342 | **98.781** | 75.643 | 75.835 |
| `hash_join` | 5.592 | 210.602 | **216.194** | 119.392 | 111.002 |
| `sieve` | 3.047 | 90.886 | **93.933** | 77.544 | 89.028 |
| `fib` | 2.773 | 83.402 | **86.175** | 65.836 | 67.496 |
| `collatz` | 2.999 | 91.658 | **94.657** | 69.353 | 70.690 |
| `matmul` | 3.311 | 97.123 | **100.434** | 81.042 | 90.992 |
| `json_parse` | 42.708 | 539.435 | **582.143** | 127.345 | 178.083 |
| `nbody` | 4.531 | 106.372 | **110.903** | 95.875 | 92.912 |

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
