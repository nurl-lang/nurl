# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T08:17:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3b6acdfe90ee71be9cf26a50c2adc6fd80dadeb2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30525842548 |
| NURL | `v0.29.0-5-g3b6acdf` |
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
| _(floor: empty program)_ | _1.404_ | _1.490_ | _1.615_ | _19.919_ | _14.085_ |
| `lcg` | **34.562** | 34.584 | 34.691 | 1422.265 | 4140.546 |
| `packet_classifier` | **49.607** | 49.672 | 49.740 | 124.614 | 3613.352 |
| `ring_write` | 37.355 | **37.351** | 37.465 | 58.171 | 5252.895 |
| `histogram_bins` | **34.826** | 34.890 | 34.920 | 59.389 | 4870.847 |
| `prefix_scan` | **19.298** | 19.335 | 19.466 | 56.918 | 3702.349 |
| `binary_search` | **27.692** | 27.925 | 35.790 | 86.881 | 5143.267 |
| `sort_window` | 24.208 | 24.353 | **23.876** | 129.830 | 8792.077 |
| `bloom_filter` | **15.483** | 15.932 | 16.245 | 2116.455 | 6064.308 |
| `hash_join` | **22.941** | 24.182 | 24.211 | 2647.200 | 6417.601 |
| `sieve` | 16.646 | 16.293 | **16.265** | 58.745 | 2748.417 |
| `fib` | **22.019** | 26.149 | 22.999 | 112.075 | 1005.308 |
| `collatz` | **10.822** | 10.903 | 10.999 | 41.619 | 584.869 |
| `matmul` | **35.591** | 36.009 | 35.991 | 65.821 | 2716.648 |
| `json_parse` | **6.528** | 7.284 | 9.731 | 30.891 | 29.494 |
| `nbody` | 36.022 | 36.033 | **34.392** | 75.248 | 2572.383 |

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
| _(floor: empty program)_ | _2.574_ | _71.778_ | _**74.352**_ | _81.581_ | _54.135_ |
| `lcg` | 2.779 | 74.898 | **77.677** | 60.092 | 62.542 |
| `packet_classifier` | 2.850 | 80.819 | **83.669** | 78.149 | 63.209 |
| `ring_write` | 3.081 | 81.289 | **84.370** | 63.510 | 62.927 |
| `histogram_bins` | 3.143 | 83.161 | **86.304** | 63.751 | 64.875 |
| `prefix_scan` | 3.203 | 84.888 | **88.091** | 66.275 | 64.790 |
| `binary_search` | 3.383 | 81.464 | **84.847** | 63.053 | 66.387 |
| `sort_window` | 3.462 | 87.007 | **90.469** | 67.064 | 68.165 |
| `bloom_filter` | 3.652 | 83.798 | **87.450** | 138.665 | 66.666 |
| `hash_join` | 7.236 | 170.325 | **177.561** | 102.551 | 95.626 |
| `sieve` | 3.237 | 83.664 | **86.901** | 70.681 | 71.572 |
| `fib` | 2.749 | 77.486 | **80.235** | 61.806 | 59.854 |
| `collatz` | 3.042 | 83.109 | **86.151** | 62.260 | 62.985 |
| `matmul` | 3.722 | 85.454 | **89.176** | 69.893 | 81.278 |
| `json_parse` | 61.538 | 542.385 | **603.923** | 203.976 | 149.780 |
| `nbody` | 5.586 | 92.661 | **98.247** | 80.780 | 80.814 |

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
