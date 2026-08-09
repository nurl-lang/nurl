# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-09T20:10:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `c9a445586b3ae1058f6ca539b3d94c176ab189ad` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31333375598 |
| NURL | `v0.36.0-41-gc9a44558` |
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
| _(floor: empty program)_ | _1.267_ | _1.300_ | _1.404_ | _16.590_ | _11.954_ |
| `lcg` | 30.486 | **30.340** | 30.379 | 1056.218 | 3178.716 |
| `packet_classifier` | **49.793** | 52.521 | 53.409 | 129.812 | 2634.180 |
| `ring_write` | 33.656 | **33.596** | 33.922 | 53.185 | 3917.466 |
| `histogram_bins` | **32.175** | 33.031 | 32.227 | 53.111 | 3818.323 |
| `prefix_scan` | **17.325** | 17.477 | 17.582 | 52.211 | 2893.820 |
| `binary_search` | 25.877 | **22.798** | 34.370 | 86.431 | 4042.888 |
| `sort_window` | 32.489 | 39.394 | **31.695** | 140.193 | 7094.875 |
| `bloom_filter` | 11.168 | **11.033** | 11.036 | 1840.713 | 4931.044 |
| `hash_join` | **18.553** | 20.066 | 20.231 | 2276.874 | 5256.985 |
| `sieve` | 33.932 | 33.503 | **33.032** | 70.710 | 2105.518 |
| `fib` | **17.897** | 21.198 | 20.519 | 88.031 | 687.137 |
| `collatz` | **11.467** | 11.594 | 12.333 | 46.248 | 424.443 |
| `matmul` | 15.423 | 15.263 | **15.216** | 55.579 | 1944.091 |
| `json_parse` | 25.794 | **5.894** | 7.205 | 26.386 | 25.741 |
| `nbody` | 23.843 | 23.940 | **22.425** | 64.319 | 1654.376 |

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
| _(floor: empty program)_ | _1.975_ | _59.929_ | _**61.904**_ | _41.418_ | _51.844_ |
| `lcg` | 2.106 | 64.823 | **66.929** | 48.199 | 55.884 |
| `packet_classifier` | 2.195 | 63.418 | **65.613** | 51.785 | 57.075 |
| `ring_write` | 2.272 | 69.100 | **71.372** | 52.599 | 60.137 |
| `histogram_bins` | 2.565 | 72.233 | **74.798** | 56.395 | 62.604 |
| `prefix_scan` | 2.414 | 71.339 | **73.753** | 53.781 | 59.894 |
| `binary_search` | 2.560 | 71.263 | **73.823** | 51.500 | 64.115 |
| `sort_window` | 2.506 | 73.867 | **76.373** | 58.197 | 67.531 |
| `bloom_filter` | 2.722 | 72.673 | **75.395** | 59.399 | 64.546 |
| `hash_join` | 4.125 | 144.183 | **148.308** | 85.764 | 91.046 |
| `sieve` | 2.332 | 67.045 | **69.377** | 56.589 | 66.783 |
| `fib` | 2.199 | 64.165 | **66.364** | 55.161 | 57.539 |
| `collatz` | 2.434 | 67.378 | **69.812** | 51.638 | 59.479 |
| `matmul` | 2.457 | 72.354 | **74.811** | 57.339 | 77.001 |
| `json_parse` | 28.717 | 353.175 | **381.892** | 83.505 | 146.364 |
| `nbody` | 3.179 | 78.856 | **82.035** | 69.045 | 77.563 |

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
