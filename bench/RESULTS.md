# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T14:08:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372444 KiB |
| Commit | `386ccf726d780f87508d644c2defab16699aa6b1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30549860533 |
| NURL | `v0.29.0-31-g386ccf7` |
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
| _(floor: empty program)_ | _1.287_ | _1.397_ | _1.443_ | _20.610_ | _15.285_ |
| `lcg` | **37.525** | 37.745 | 37.580 | 1361.743 | 3929.876 |
| `packet_classifier` | **58.981** | 64.641 | 63.444 | 153.247 | 3263.159 |
| `ring_write` | 40.194 | **39.981** | 40.227 | 59.538 | 4753.627 |
| `histogram_bins` | 40.066 | **38.792** | 39.026 | 65.401 | 4395.391 |
| `prefix_scan` | 20.395 | **20.317** | 20.976 | 61.519 | 3393.412 |
| `binary_search` | 32.037 | **28.727** | 40.213 | 100.738 | 4769.749 |
| `sort_window` | 40.377 | 50.670 | **39.824** | 171.533 | 8908.184 |
| `bloom_filter` | **13.008** | 13.256 | 13.086 | 2158.749 | 6098.273 |
| `hash_join` | **22.028** | 24.530 | 25.205 | 2719.142 | 6328.267 |
| `sieve` | **33.878** | 34.395 | 33.984 | 77.471 | 2372.641 |
| `fib` | 26.754 | 27.611 | **23.504** | 101.683 | 806.550 |
| `collatz` | **13.811** | 13.960 | 14.375 | 57.048 | 511.488 |
| `matmul` | 18.527 | **18.356** | 18.709 | 68.047 | 2258.899 |
| `json_parse` | **6.541** | 6.993 | 9.000 | 29.559 | 29.382 |
| `nbody` | 29.136 | 29.633 | **28.389** | 75.602 | 1912.026 |

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
| _(floor: empty program)_ | _2.329_ | _65.599_ | _**67.928**_ | _46.513_ | _56.936_ |
| `lcg` | 2.592 | 71.030 | **73.622** | 53.831 | 62.817 |
| `packet_classifier` | 2.549 | 70.221 | **72.770** | 55.331 | 61.981 |
| `ring_write` | 2.672 | 73.033 | **75.705** | 54.186 | 62.644 |
| `histogram_bins` | 2.851 | 80.680 | **83.531** | 57.145 | 66.560 |
| `prefix_scan` | 2.864 | 75.671 | **78.535** | 58.106 | 64.679 |
| `binary_search` | 2.969 | 74.379 | **77.348** | 55.223 | 66.605 |
| `sort_window` | 3.216 | 81.223 | **84.439** | 61.347 | 70.831 |
| `bloom_filter` | 3.229 | 79.313 | **82.542** | 61.934 | 67.619 |
| `hash_join` | 6.598 | 165.267 | **171.865** | 95.589 | 100.448 |
| `sieve` | 2.808 | 75.513 | **78.321** | 62.972 | 78.951 |
| `fib` | 2.439 | 68.319 | **70.758** | 54.516 | 60.104 |
| `collatz` | 2.672 | 73.832 | **76.504** | 56.461 | 64.030 |
| `matmul` | 3.390 | 79.493 | **82.883** | 66.501 | 85.367 |
| `json_parse` | 54.189 | 573.831 | **628.020** | 98.522 | 171.811 |
| `nbody` | 4.822 | 90.264 | **95.086** | 80.455 | 84.160 |

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
