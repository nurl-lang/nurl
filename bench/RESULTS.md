# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T04:21:14Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `4db29288ac2baf13bcae9969606cd00a02a0109d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31458001062 |
| NURL | `v0.36.0-96-g4db29288` |
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
| _(floor: empty program)_ | _1.427_ | _1.465_ | _1.587_ | _19.418_ | _14.689_ |
| `lcg` | **34.403** | 34.534 | 34.569 | 1418.830 | 4164.390 |
| `packet_classifier` | **49.554** | 49.559 | 49.652 | 123.155 | 3565.740 |
| `ring_write` | **37.166** | 37.171 | 37.262 | 57.281 | 5407.211 |
| `histogram_bins` | **34.834** | 34.858 | 34.936 | 59.405 | 4858.562 |
| `prefix_scan` | 19.215 | **19.179** | 19.355 | 56.389 | 3563.425 |
| `binary_search` | 27.922 | **27.907** | 35.840 | 87.235 | 5188.091 |
| `sort_window` | 24.023 | 24.033 | **23.665** | 129.344 | 8824.244 |
| `bloom_filter` | **15.456** | 15.915 | 16.180 | 2147.484 | 5904.877 |
| `hash_join` | **22.828** | 23.985 | 24.269 | 2737.572 | 6259.320 |
| `sieve` | 16.234 | 16.369 | **16.153** | 55.663 | 2668.798 |
| `fib` | **21.885** | 26.054 | 23.098 | 112.235 | 1039.000 |
| `collatz` | 10.822 | **10.782** | 10.926 | 41.172 | 583.910 |
| `matmul` | 36.267 | 36.312 | **35.563** | 65.239 | 2939.720 |
| `json_parse` | 36.864 | **7.158** | 9.681 | 31.007 | 30.684 |
| `nbody` | 35.954 | 36.119 | **34.374** | 77.691 | 2596.179 |

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
| _(floor: empty program)_ | _2.415_ | _70.908_ | _**73.323**_ | _52.067_ | _53.341_ |
| `lcg` | 2.489 | 74.791 | **77.280** | 59.890 | 59.925 |
| `packet_classifier` | 2.621 | 78.167 | **80.788** | 60.962 | 60.031 |
| `ring_write` | 2.645 | 78.339 | **80.984** | 61.653 | 61.182 |
| `histogram_bins` | 2.751 | 83.257 | **86.008** | 63.238 | 63.413 |
| `prefix_scan` | 2.733 | 81.831 | **84.564** | 63.299 | 62.555 |
| `binary_search` | 2.786 | 80.542 | **83.328** | 61.602 | 65.649 |
| `sort_window` | 2.847 | 86.209 | **89.056** | 66.670 | 69.164 |
| `bloom_filter` | 2.956 | 84.275 | **87.231** | 65.770 | 64.734 |
| `hash_join` | 4.619 | 165.603 | **170.222** | 96.834 | 92.027 |
| `sieve` | 2.676 | 81.991 | **84.667** | 67.634 | 68.575 |
| `fib` | 2.479 | 75.202 | **77.681** | 60.536 | 58.159 |
| `collatz` | 2.645 | 78.804 | **81.449** | 60.522 | 62.011 |
| `matmul` | 2.875 | 102.884 | **105.759** | 70.963 | 78.087 |
| `json_parse` | 32.555 | 406.871 | **439.426** | 98.677 | 149.767 |
| `nbody` | 3.727 | 94.478 | **98.205** | 80.944 | 80.326 |

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
