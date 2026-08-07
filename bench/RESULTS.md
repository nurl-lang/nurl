# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T23:23:07Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `d6da0b80d10c205a4211c8d02a2175b8dea95226` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31226750569 |
| NURL | `v0.35.1-6-gd6da0b80` |
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
| _(floor: empty program)_ | _1.291_ | _1.301_ | _1.400_ | _20.380_ | _13.868_ |
| `lcg` | 35.364 | 35.347 | **35.226** | 1295.405 | 3808.261 |
| `packet_classifier` | **56.366** | 61.836 | 60.114 | 147.149 | 3065.354 |
| `ring_write` | 38.698 | **38.519** | 38.935 | 56.624 | 4582.199 |
| `histogram_bins` | 36.455 | **36.044** | 36.314 | 59.401 | 4132.292 |
| `prefix_scan` | **19.323** | 19.794 | 19.841 | 57.358 | 3246.573 |
| `binary_search` | 29.821 | **27.631** | 38.824 | 96.500 | 4612.086 |
| `sort_window` | 36.155 | 45.187 | **35.198** | 157.332 | 8303.208 |
| `bloom_filter` | 12.791 | **12.468** | 12.650 | 2103.462 | 5746.348 |
| `hash_join` | **21.211** | 23.361 | 23.545 | 2623.059 | 6065.335 |
| `sieve` | 33.573 | **33.277** | 33.435 | 73.666 | 2320.659 |
| `fib` | 26.023 | 26.320 | **22.550** | 97.450 | 782.527 |
| `collatz` | **13.177** | 13.386 | 14.085 | 50.217 | 490.306 |
| `matmul` | 17.824 | 17.919 | **17.820** | 64.076 | 2171.054 |
| `json_parse` | 31.005 | **6.800** | 8.522 | 27.749 | 28.537 |
| `nbody` | 28.274 | 28.286 | **26.032** | 72.085 | 1851.971 |

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
| _(floor: empty program)_ | _2.119_ | _60.664_ | _**62.783**_ | _40.205_ | _51.092_ |
| `lcg` | 2.129 | 62.120 | **64.249** | 44.865 | 56.527 |
| `packet_classifier` | 2.179 | 60.695 | **62.874** | 47.213 | 57.716 |
| `ring_write` | 2.286 | 65.331 | **67.617** | 46.086 | 57.642 |
| `histogram_bins` | 2.359 | 64.645 | **67.004** | 49.650 | 57.574 |
| `prefix_scan` | 2.400 | 64.943 | **67.343** | 48.551 | 59.440 |
| `binary_search` | 2.441 | 63.884 | **66.325** | 49.044 | 62.257 |
| `sort_window` | 2.466 | 69.359 | **71.825** | 53.410 | 64.591 |
| `bloom_filter` | 2.641 | 68.464 | **71.105** | 52.823 | 63.487 |
| `hash_join` | 4.428 | 157.642 | **162.070** | 87.974 | 95.585 |
| `sieve` | 2.350 | 68.028 | **70.378** | 53.528 | 65.760 |
| `fib` | 2.136 | 61.064 | **63.200** | 44.179 | 54.085 |
| `collatz` | 2.328 | 62.879 | **65.207** | 47.899 | 57.742 |
| `matmul` | 2.617 | 68.617 | **71.234** | 53.643 | 77.030 |
| `json_parse` | 33.528 | 404.819 | **438.347** | 87.526 | 157.807 |
| `nbody` | 3.196 | 78.565 | **81.761** | 66.939 | 78.982 |

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
