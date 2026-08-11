# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T16:52:23Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377736 KiB |
| Commit | `ee448e968f20ee0611df4d27670a08e799f1f782` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31514263902 |
| NURL | `v0.37.1-13-gee448e96` |
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
| _(floor: empty program)_ | _1.642_ | _1.727_ | _1.866_ | _22.757_ | _16.944_ |
| `lcg` | **39.250** | **39.250** | 39.346 | 1879.070 | 5130.702 |
| `packet_classifier` | **56.481** | 56.629 | 56.687 | 161.261 | 4361.286 |
| `ring_write` | **42.367** | 42.486 | 42.538 | 66.638 | 6273.219 |
| `histogram_bins` | **39.674** | 41.383 | 39.818 | 64.833 | 5914.324 |
| `prefix_scan` | **21.871** | 21.930 | 22.055 | 63.970 | 4465.195 |
| `binary_search` | 39.914 | **38.474** | 43.505 | 105.849 | 5912.751 |
| `sort_window` | 27.378 | 27.405 | **26.889** | 197.416 | 12095.444 |
| `bloom_filter` | **18.107** | 18.328 | 18.545 | 2803.177 | 7902.807 |
| `hash_join` | **28.051** | 30.272 | 29.938 | 3433.572 | 8236.940 |
| `sieve` | 18.821 | **18.179** | 18.589 | 65.976 | 3634.758 |
| `fib` | **25.359** | 30.002 | 28.445 | 133.462 | 1337.000 |
| `collatz` | **12.523** | 12.928 | 12.671 | 48.221 | 713.350 |
| `matmul` | 33.702 | **33.544** | 33.707 | 75.117 | 3415.995 |
| `json_parse` | **8.786** | 8.875 | 11.778 | 36.111 | 37.321 |
| `nbody` | 40.841 | 40.922 | **39.012** | 100.743 | 3045.787 |

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
| _(floor: empty program)_ | _2.646_ | _78.879_ | _**81.525**_ | _59.143_ | _61.662_ |
| `lcg` | 2.849 | 84.728 | **87.577** | 65.485 | 67.805 |
| `packet_classifier` | 2.869 | 86.112 | **88.981** | 66.424 | 67.823 |
| `ring_write` | 2.958 | 86.150 | **89.108** | 66.763 | 68.890 |
| `histogram_bins` | 3.094 | 90.838 | **93.932** | 69.528 | 72.229 |
| `prefix_scan` | 3.083 | 92.240 | **95.323** | 71.267 | 70.858 |
| `binary_search` | 3.184 | 91.305 | **94.489** | 68.896 | 76.398 |
| `sort_window` | 3.247 | 97.650 | **100.897** | 75.065 | 80.143 |
| `bloom_filter` | 3.465 | 95.904 | **99.369** | 76.049 | 74.467 |
| `hash_join` | 5.562 | 210.161 | **215.723** | 118.792 | 110.870 |
| `sieve` | 3.023 | 92.020 | **95.043** | 77.676 | 80.398 |
| `fib` | 2.813 | 85.799 | **88.612** | 67.549 | 68.089 |
| `collatz` | 2.954 | 90.792 | **93.746** | 68.061 | 69.842 |
| `matmul` | 3.291 | 95.514 | **98.805** | 79.017 | 91.745 |
| `json_parse` | 43.322 | 533.098 | **576.420** | 122.633 | 178.936 |
| `nbody` | 4.365 | 105.991 | **110.356** | 96.442 | 92.215 |

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
