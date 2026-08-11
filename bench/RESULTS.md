# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T03:27:08Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d51be0a50f8a081ff61d791586fbe2457796280b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31455198719 |
| NURL | `v0.36.0-90-gd51be0a5` |
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
| _(floor: empty program)_ | _1.864_ | _1.843_ | _2.039_ | _24.583_ | _18.543_ |
| `lcg` | **44.381** | 44.467 | 44.572 | 1834.447 | 5575.252 |
| `packet_classifier` | 63.824 | **63.796** | 64.143 | 161.352 | 4589.163 |
| `ring_write` | **47.883** | 47.957 | 48.067 | 73.674 | 6483.382 |
| `histogram_bins` | **44.885** | 44.952 | 45.089 | 76.345 | 6194.211 |
| `prefix_scan` | **24.678** | 24.760 | 24.887 | 71.393 | 4743.564 |
| `binary_search` | **35.423** | 36.009 | 46.095 | 111.329 | 6351.921 |
| `sort_window` | 30.984 | 31.158 | **30.425** | 167.699 | 11164.179 |
| `bloom_filter` | **19.926** | 20.501 | 20.888 | 2720.935 | 7704.692 |
| `hash_join` | **29.360** | 30.931 | 31.384 | 3376.258 | 8076.027 |
| `sieve` | 20.772 | **20.336** | 20.402 | 73.592 | 3351.653 |
| `fib` | **28.063** | 33.431 | 29.446 | 143.607 | 1292.665 |
| `collatz` | **13.931** | 13.991 | 14.087 | 52.737 | 751.600 |
| `matmul` | 46.671 | **46.348** | 46.506 | 85.060 | 3426.879 |
| `json_parse` | 45.662 | **9.147** | 12.385 | 38.105 | 38.707 |
| `nbody` | 46.285 | 46.495 | **44.211** | 96.721 | 3560.443 |

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
| _(floor: empty program)_ | _3.044_ | _94.813_ | _**97.857**_ | _67.799_ | _66.702_ |
| `lcg` | 3.166 | 100.527 | **103.693** | 78.162 | 75.957 |
| `packet_classifier` | 3.261 | 99.841 | **103.102** | 78.244 | 75.925 |
| `ring_write` | 3.335 | 99.859 | **103.194** | 76.637 | 78.437 |
| `histogram_bins` | 3.405 | 105.243 | **108.648** | 81.637 | 82.162 |
| `prefix_scan` | 3.478 | 104.038 | **107.516** | 81.901 | 79.629 |
| `binary_search` | 3.598 | 102.224 | **105.822** | 79.051 | 83.837 |
| `sort_window` | 3.622 | 110.598 | **114.220** | 86.175 | 88.038 |
| `bloom_filter` | 3.868 | 108.130 | **111.998** | 83.812 | 81.687 |
| `hash_join` | 6.086 | 214.533 | **220.619** | 124.467 | 118.693 |
| `sieve` | 3.442 | 105.771 | **109.213** | 87.490 | 87.235 |
| `fib` | 3.143 | 97.911 | **101.054** | 74.588 | 75.687 |
| `collatz` | 3.352 | 100.073 | **103.425** | 77.457 | 77.668 |
| `matmul` | 3.630 | 109.554 | **113.184** | 89.027 | 101.945 |
| `json_parse` | 42.646 | 524.245 | **566.891** | 129.449 | 190.601 |
| `nbody` | 4.812 | 119.907 | **124.719** | 103.765 | 101.642 |

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
