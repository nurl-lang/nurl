# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T10:42:31Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `701df62fbbb9645ea3c7374126475108fce7b20d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30696088875 |
| NURL | `v0.30.0-14-g701df62` |
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
| _(floor: empty program)_ | _1.468_ | _1.477_ | _1.639_ | _20.842_ | _14.785_ |
| `lcg` | 34.430 | **34.418** | 34.625 | 1416.422 | 4124.080 |
| `packet_classifier` | **49.604** | 49.669 | 49.810 | 122.510 | 3575.142 |
| `ring_write` | 37.342 | **37.231** | 37.351 | 57.176 | 5004.282 |
| `histogram_bins` | **34.955** | 35.238 | 35.086 | 57.879 | 5179.416 |
| `prefix_scan` | **19.288** | 19.296 | 19.435 | 57.822 | 3719.864 |
| `binary_search` | **27.757** | 27.902 | 35.832 | 87.647 | 5020.307 |
| `sort_window` | 24.169 | 24.025 | **23.573** | 128.947 | 8533.522 |
| `bloom_filter` | **15.455** | 15.938 | 16.138 | 2146.007 | 5960.305 |
| `hash_join` | **22.909** | 24.044 | 24.231 | 2603.649 | 6453.675 |
| `sieve` | 16.407 | 16.249 | **16.126** | 56.319 | 2655.731 |
| `fib` | **21.876** | 26.102 | 22.968 | 110.425 | 996.812 |
| `collatz` | **10.910** | 10.926 | 11.051 | 41.474 | 587.007 |
| `matmul` | 36.620 | **36.228** | 36.258 | 66.273 | 2665.971 |
| `json_parse` | **6.707** | 7.197 | 9.618 | 30.334 | 30.710 |
| `nbody` | 36.130 | 36.194 | **34.533** | 76.869 | 2512.900 |

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
| _(floor: empty program)_ | _2.326_ | _68.303_ | _**70.629**_ | _67.165_ | _55.788_ |
| `lcg` | 2.436 | 77.352 | **79.788** | 60.331 | 61.781 |
| `packet_classifier` | 2.512 | 78.064 | **80.576** | 59.685 | 60.587 |
| `ring_write` | 2.601 | 79.851 | **82.452** | 62.771 | 62.510 |
| `histogram_bins` | 2.622 | 82.076 | **84.698** | 61.647 | 62.873 |
| `prefix_scan` | 2.679 | 83.597 | **86.276** | 65.671 | 65.257 |
| `binary_search` | 2.746 | 79.390 | **82.136** | 62.213 | 67.092 |
| `sort_window` | 2.809 | 88.542 | **91.351** | 98.433 | 68.405 |
| `bloom_filter` | 2.906 | 83.051 | **85.957** | 67.883 | 67.867 |
| `hash_join` | 4.499 | 165.290 | **169.789** | 97.936 | 92.923 |
| `sieve` | 2.656 | 82.128 | **84.784** | 68.299 | 69.684 |
| `fib` | 2.427 | 73.451 | **75.878** | 93.525 | 58.631 |
| `collatz` | 2.532 | 78.043 | **80.575** | 60.491 | 62.751 |
| `matmul` | 2.823 | 85.365 | **88.188** | 70.158 | 82.238 |
| `json_parse` | 31.528 | 393.706 | **425.234** | 102.169 | 152.118 |
| `nbody` | 3.669 | 94.601 | **98.270** | 81.391 | 81.821 |

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
