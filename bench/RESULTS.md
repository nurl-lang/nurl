# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T04:32:02Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `b05b5588880fe6168a246164ba83f2ff5f41f745` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30877756694 |
| NURL | `v0.32.0-19-gb05b5588` |
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
| _(floor: empty program)_ | _1.428_ | _1.449_ | _1.599_ | _18.333_ | _13.992_ |
| `lcg` | **34.297** | 34.449 | 34.486 | 1420.822 | 4095.127 |
| `packet_classifier` | **49.446** | 49.475 | 49.590 | 122.822 | 3523.961 |
| `ring_write` | **37.044** | 37.139 | 37.231 | 56.847 | 5269.792 |
| `histogram_bins` | **34.758** | 34.845 | 34.860 | 58.726 | 4952.399 |
| `prefix_scan` | **19.156** | 19.209 | 19.313 | 56.088 | 3831.840 |
| `binary_search` | 28.101 | **27.852** | 35.744 | 86.503 | 5637.823 |
| `sort_window` | 23.979 | 23.987 | **23.549** | 130.189 | 8612.317 |
| `bloom_filter` | **15.450** | 15.914 | 16.211 | 2141.024 | 6301.673 |
| `hash_join` | **22.754** | 24.066 | 24.269 | 2629.762 | 6158.413 |
| `sieve` | 16.475 | **15.749** | 15.927 | 54.722 | 2787.374 |
| `fib` | **21.736** | 25.891 | 22.857 | 111.170 | 1005.649 |
| `collatz` | **10.830** | 10.858 | 10.910 | 40.350 | 587.468 |
| `matmul` | **35.576** | 36.449 | 36.039 | 66.153 | 2750.120 |
| `json_parse` | **6.544** | 7.087 | 9.585 | 29.695 | 29.476 |
| `nbody` | 35.926 | 36.038 | **34.344** | 74.731 | 2532.192 |

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
| _(floor: empty program)_ | _2.249_ | _68.645_ | _**70.894**_ | _51.086_ | _53.154_ |
| `lcg` | 2.381 | 73.238 | **75.619** | 57.337 | 59.103 |
| `packet_classifier` | 2.455 | 74.618 | **77.073** | 59.242 | 59.963 |
| `ring_write` | 2.557 | 75.859 | **78.416** | 60.387 | 60.863 |
| `histogram_bins` | 2.623 | 77.725 | **80.348** | 61.045 | 63.319 |
| `prefix_scan` | 2.611 | 78.374 | **80.985** | 62.053 | 62.970 |
| `binary_search` | 2.695 | 77.975 | **80.670** | 59.373 | 63.960 |
| `sort_window` | 2.764 | 82.972 | **85.736** | 65.121 | 67.470 |
| `bloom_filter` | 2.863 | 81.960 | **84.823** | 65.260 | 65.068 |
| `hash_join` | 4.523 | 166.474 | **170.997** | 96.008 | 91.969 |
| `sieve` | 2.620 | 79.297 | **81.917** | 66.313 | 68.554 |
| `fib` | 2.363 | 72.815 | **75.178** | 57.863 | 60.609 |
| `collatz` | 2.527 | 76.555 | **79.082** | 59.261 | 61.340 |
| `matmul` | 2.765 | 81.363 | **84.128** | 68.042 | 78.513 |
| `json_parse` | 31.250 | 386.551 | **417.801** | 99.165 | 148.036 |
| `nbody` | 3.623 | 90.404 | **94.027** | 79.018 | 79.347 |

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
