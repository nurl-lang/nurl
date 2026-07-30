# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T21:05:57Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377688 KiB |
| Commit | `ca377d0f229e24770680b17a0faf9e139aaac0b0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30581635784 |
| NURL | `v0.29.0-68-gca377d0` |
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
| _(floor: empty program)_ | _1.670_ | _1.788_ | _1.879_ | _24.827_ | _17.595_ |
| `lcg` | **39.378** | 39.519 | 39.597 | 1883.169 | 5151.876 |
| `packet_classifier` | **56.408** | 56.472 | 56.761 | 162.290 | 4510.024 |
| `ring_write` | 42.373 | **42.349** | 42.673 | 66.342 | 6196.835 |
| `histogram_bins` | **39.730** | 41.453 | 39.921 | 67.478 | 6008.166 |
| `prefix_scan` | **21.989** | 22.115 | 22.084 | 64.637 | 4668.362 |
| `binary_search` | 39.945 | **38.602** | 43.313 | 106.548 | 14479.916 |
| `sort_window` | 27.478 | 27.537 | **27.032** | 196.375 | 13785.342 |
| `bloom_filter` | **18.019** | 18.422 | 18.638 | 2824.312 | 7353.441 |
| `hash_join` | **28.337** | 30.363 | 30.194 | 3422.890 | 8183.264 |
| `sieve` | 18.523 | 18.329 | **18.317** | 66.747 | 3546.971 |
| `fib` | **25.324** | 30.160 | 28.650 | 132.583 | 1342.404 |
| `collatz` | **12.552** | 12.565 | 12.666 | 50.189 | 713.035 |
| `matmul` | 33.629 | **33.595** | 33.704 | 75.976 | 3070.112 |
| `json_parse` | **8.577** | 9.039 | 11.840 | 38.425 | 37.749 |
| `nbody` | 41.109 | 41.150 | **39.153** | 101.996 | 3149.585 |

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
| _(floor: empty program)_ | _3.223_ | _83.362_ | _**86.585**_ | _60.131_ | _68.370_ |
| `lcg` | 3.297 | 89.791 | **93.088** | 70.071 | 71.033 |
| `packet_classifier` | 3.293 | 86.044 | **89.337** | 69.353 | 67.934 |
| `ring_write` | 3.465 | 88.781 | **92.246** | 70.572 | 70.155 |
| `histogram_bins` | 3.619 | 91.435 | **95.054** | 73.059 | 73.478 |
| `prefix_scan` | 3.688 | 91.319 | **95.007** | 72.775 | 72.374 |
| `binary_search` | 3.967 | 91.906 | **95.873** | 70.009 | 78.735 |
| `sort_window` | 4.101 | 98.286 | **102.387** | 76.951 | 78.846 |
| `bloom_filter` | 4.319 | 97.887 | **102.206** | 76.290 | 76.320 |
| `hash_join` | 8.794 | 210.471 | **219.265** | 121.528 | 110.317 |
| `sieve` | 3.706 | 92.974 | **96.680** | 81.270 | 86.340 |
| `fib` | 3.208 | 86.964 | **90.172** | 68.088 | 67.643 |
| `collatz` | 3.589 | 90.142 | **93.731** | 68.460 | 71.738 |
| `matmul` | 4.374 | 97.219 | **101.593** | 83.644 | 92.432 |
| `json_parse` | 75.169 | 731.015 | **806.184** | 126.244 | 180.523 |
| `nbody` | 6.927 | 108.598 | **115.525** | 98.174 | 93.316 |

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
