# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T16:34:47Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a1f02e9755cab143354e8479521643d2a87385bf` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30561689034 |
| NURL | `v0.29.0-40-ga1f02e9` |
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
| _(floor: empty program)_ | _1.817_ | _1.847_ | _2.020_ | _26.263_ | _18.175_ |
| `lcg` | 44.362 | **44.303** | 44.534 | 1824.753 | 5468.532 |
| `packet_classifier` | **63.696** | 63.765 | 63.881 | 158.976 | 4596.558 |
| `ring_write` | **47.944** | 47.991 | 48.041 | 73.877 | 7087.365 |
| `histogram_bins` | 44.853 | **44.837** | 45.009 | 74.999 | 6419.348 |
| `prefix_scan` | **24.689** | 24.732 | 24.897 | 71.663 | 4922.499 |
| `binary_search` | **36.028** | 36.048 | 46.219 | 112.407 | 7170.571 |
| `sort_window` | 31.019 | 31.126 | **30.637** | 166.347 | 10842.447 |
| `bloom_filter` | **19.975** | 20.633 | 20.942 | 2789.959 | 7924.728 |
| `hash_join` | **29.485** | 30.930 | 31.370 | 3443.679 | 8434.325 |
| `sieve` | 21.006 | **20.647** | 20.868 | 72.198 | 3484.627 |
| `fib` | **28.108** | 33.390 | 29.646 | 143.538 | 1287.173 |
| `collatz` | **13.926** | 14.015 | 14.127 | 53.285 | 762.100 |
| `matmul` | **45.070** | 46.043 | 46.039 | 82.937 | 3330.014 |
| `json_parse` | **8.392** | 9.126 | 12.452 | 40.046 | 39.625 |
| `nbody` | 46.420 | 46.593 | **44.371** | 97.309 | 3157.673 |

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
| _(floor: empty program)_ | _3.576_ | _90.644_ | _**94.220**_ | _65.494_ | _65.311_ |
| `lcg` | 3.572 | 92.872 | **96.444** | 74.406 | 74.342 |
| `packet_classifier` | 3.659 | 93.458 | **97.117** | 76.063 | 73.448 |
| `ring_write` | 3.894 | 95.326 | **99.220** | 75.828 | 75.302 |
| `histogram_bins` | 4.087 | 100.722 | **104.809** | 78.491 | 77.923 |
| `prefix_scan` | 4.191 | 102.627 | **106.818** | 82.168 | 79.874 |
| `binary_search` | 4.350 | 100.868 | **105.218** | 75.035 | 79.865 |
| `sort_window` | 4.533 | 107.402 | **111.935** | 82.944 | 83.746 |
| `bloom_filter` | 4.926 | 106.959 | **111.885** | 84.640 | 89.084 |
| `hash_join` | 9.512 | 209.754 | **219.266** | 122.586 | 115.553 |
| `sieve` | 4.231 | 102.417 | **106.648** | 85.542 | 85.038 |
| `fib` | 3.634 | 97.524 | **101.158** | 78.806 | 74.182 |
| `collatz` | 4.009 | 100.084 | **104.093** | 77.708 | 77.960 |
| `matmul` | 4.828 | 104.077 | **108.905** | 88.137 | 101.415 |
| `json_parse` | 77.588 | 719.467 | **797.055** | 127.474 | 188.218 |
| `nbody` | 7.368 | 118.964 | **126.332** | 101.512 | 100.173 |

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
