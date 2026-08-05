# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T17:09:31Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `e1fda617a9b1221141b1b534498770c28f2a1ca5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31028299126 |
| NURL | `v0.33.0-19-ge1fda617` |
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
| _(floor: empty program)_ | _1.681_ | _1.796_ | _1.966_ | _24.253_ | _17.742_ |
| `lcg` | **39.395** | 39.490 | 39.722 | 1881.372 | 5562.551 |
| `packet_classifier` | **56.557** | 56.607 | 56.829 | 163.501 | 4703.462 |
| `ring_write` | 42.691 | **42.618** | 42.750 | 68.453 | 6422.492 |
| `histogram_bins` | **39.910** | 41.582 | 40.051 | 67.479 | 6090.557 |
| `prefix_scan` | **21.905** | 21.961 | 22.143 | 66.855 | 4630.667 |
| `binary_search` | 40.043 | **38.309** | 43.373 | 106.600 | 5986.541 |
| `sort_window` | 27.489 | 27.459 | **27.056** | 198.502 | 11575.162 |
| `bloom_filter` | **18.109** | 18.326 | 18.582 | 2826.850 | 7543.497 |
| `hash_join` | **27.981** | 30.245 | 30.066 | 3419.752 | 8283.140 |
| `sieve` | 18.509 | 18.697 | **18.398** | 67.353 | 3190.635 |
| `fib` | **25.348** | 30.179 | 28.533 | 132.954 | 1345.363 |
| `collatz` | **12.561** | 12.606 | 12.655 | 49.762 | 716.402 |
| `matmul` | 33.739 | **33.684** | 34.000 | 78.114 | 3265.873 |
| `json_parse` | **8.713** | 8.956 | 11.944 | 36.842 | 37.645 |
| `nbody` | 40.884 | 41.048 | **39.161** | 101.191 | 3118.705 |

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
| _(floor: empty program)_ | _2.786_ | _85.050_ | _**87.836**_ | _60.330_ | _84.429_ |
| `lcg` | 2.785 | 90.530 | **93.315** | 70.378 | 71.081 |
| `packet_classifier` | 2.858 | 91.716 | **94.574** | 71.201 | 70.832 |
| `ring_write` | 2.959 | 93.423 | **96.382** | 71.904 | 69.895 |
| `histogram_bins` | 2.977 | 95.837 | **98.814** | 72.231 | 72.397 |
| `prefix_scan` | 3.097 | 97.373 | **100.470** | 76.232 | 74.433 |
| `binary_search` | 3.166 | 95.853 | **99.019** | 72.787 | 76.163 |
| `sort_window` | 3.182 | 98.225 | **101.407** | 76.548 | 79.084 |
| `bloom_filter` | 3.476 | 98.499 | **101.975** | 78.648 | 77.331 |
| `hash_join` | 5.426 | 212.920 | **218.346** | 122.043 | 113.037 |
| `sieve` | 3.074 | 94.034 | **97.108** | 82.191 | 80.099 |
| `fib` | 2.777 | 86.292 | **89.069** | 67.796 | 67.881 |
| `collatz` | 2.953 | 92.828 | **95.781** | 69.911 | 69.952 |
| `matmul` | 3.292 | 102.419 | **105.711** | 81.385 | 91.210 |
| `json_parse` | 40.236 | 531.210 | **571.446** | 128.262 | 179.218 |
| `nbody` | 4.227 | 109.757 | **113.984** | 100.476 | 93.818 |

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
