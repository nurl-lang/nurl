# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-09T18:54:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `88ca417994d756d83e933ba5f6b1ce8f898e4756` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31330027397 |
| NURL | `v0.36.0-34-g88ca4179` |
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
| _(floor: empty program)_ | _1.839_ | _2.035_ | _2.074_ | _43.193_ | _19.318_ |
| `lcg` | **44.471** | 44.509 | 44.609 | 1841.146 | 5484.087 |
| `packet_classifier` | **63.781** | 63.878 | 64.011 | 160.390 | 4649.402 |
| `ring_write` | **47.983** | 48.127 | 48.168 | 74.256 | 6745.122 |
| `histogram_bins` | **44.923** | 45.034 | 45.750 | 75.193 | 6239.288 |
| `prefix_scan` | **24.673** | 24.754 | 24.943 | 71.749 | 4982.660 |
| `binary_search` | 35.990 | **35.889** | 46.198 | 112.809 | 6463.194 |
| `sort_window` | 31.074 | 31.004 | **30.524** | 171.093 | 14405.319 |
| `bloom_filter` | **19.959** | 20.595 | 20.935 | 2795.497 | 8009.436 |
| `hash_join` | **29.500** | 31.057 | 31.284 | 3367.555 | 8300.223 |
| `sieve` | 20.855 | **20.499** | 21.131 | 71.905 | 3378.581 |
| `fib` | **28.258** | 33.557 | 29.607 | 142.747 | 1292.712 |
| `collatz` | **13.971** | 13.994 | 14.059 | 51.559 | 753.461 |
| `matmul` | **45.826** | 46.683 | 46.342 | 83.865 | 3580.863 |
| `json_parse` | 45.837 | **9.085** | 12.426 | 37.199 | 38.251 |
| `nbody` | 46.342 | 46.443 | **44.264** | 96.176 | 3678.888 |

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
| _(floor: empty program)_ | _3.060_ | _91.941_ | _**95.001**_ | _65.238_ | _68.425_ |
| `lcg` | 3.192 | 99.769 | **102.961** | 76.392 | 84.650 |
| `packet_classifier` | 3.238 | 101.095 | **104.333** | 77.840 | 75.741 |
| `ring_write` | 3.356 | 99.446 | **102.802** | 77.678 | 77.943 |
| `histogram_bins` | 3.395 | 104.255 | **107.650** | 80.405 | 79.219 |
| `prefix_scan` | 3.444 | 106.791 | **110.235** | 80.696 | 79.961 |
| `binary_search` | 3.512 | 99.646 | **103.158** | 75.554 | 79.806 |
| `sort_window` | 3.617 | 111.314 | **114.931** | 84.435 | 86.317 |
| `bloom_filter` | 3.782 | 106.967 | **110.749** | 83.885 | 80.813 |
| `hash_join` | 5.971 | 215.433 | **221.404** | 125.154 | 116.939 |
| `sieve` | 3.414 | 103.250 | **106.664** | 84.618 | 85.151 |
| `fib` | 3.135 | 93.218 | **96.353** | 74.438 | 72.321 |
| `collatz` | 3.320 | 103.173 | **106.493** | 76.993 | 77.137 |
| `matmul` | 3.632 | 108.584 | **112.216** | 88.375 | 101.173 |
| `json_parse` | 42.007 | 520.285 | **562.292** | 125.688 | 186.446 |
| `nbody` | 4.750 | 114.422 | **119.172** | 99.812 | 99.543 |

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
