# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-06T09:09:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a5978c7bd0ca594f7d721f980aeee7f607ed49b8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31087539244 |
| NURL | `v0.33.0-68-ga5978c7b` |
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
| _(floor: empty program)_ | _1.813_ | _1.854_ | _2.021_ | _23.696_ | _17.763_ |
| `lcg` | **44.360** | 44.404 | 44.542 | 1829.615 | 5299.578 |
| `packet_classifier` | **63.671** | 63.764 | 63.953 | 156.711 | 4644.827 |
| `ring_write` | **47.770** | 47.937 | 48.029 | 72.872 | 9806.616 |
| `histogram_bins` | **44.738** | 44.838 | 45.028 | 75.783 | 6258.122 |
| `prefix_scan` | **24.619** | 24.681 | 24.788 | 71.318 | 4600.388 |
| `binary_search` | **35.717** | 35.932 | 46.130 | 112.227 | 6496.988 |
| `sort_window` | 30.905 | 30.908 | **30.334** | 165.301 | 10895.698 |
| `bloom_filter` | **19.895** | 20.481 | 20.868 | 2792.669 | 7827.465 |
| `hash_join` | **29.245** | 30.876 | 31.232 | 3442.602 | 8189.444 |
| `sieve` | 20.482 | 20.572 | **20.326** | 69.899 | 3446.283 |
| `fib` | **28.075** | 33.503 | 29.588 | 142.004 | 1282.512 |
| `collatz` | **13.907** | 13.950 | 14.081 | 51.754 | 762.997 |
| `matmul` | **45.733** | 46.459 | 47.506 | 83.645 | 3343.744 |
| `json_parse` | **8.633** | 9.292 | 12.372 | 37.489 | 38.049 |
| `nbody` | 46.379 | 46.515 | **44.202** | 95.956 | 3235.435 |

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
| _(floor: empty program)_ | _2.978_ | _89.037_ | _**92.015**_ | _63.972_ | _64.426_ |
| `lcg` | 3.004 | 93.638 | **96.642** | 70.702 | 72.589 |
| `packet_classifier` | 3.132 | 96.115 | **99.247** | 73.714 | 72.733 |
| `ring_write` | 3.246 | 96.464 | **99.710** | 73.770 | 73.925 |
| `histogram_bins` | 3.305 | 98.603 | **101.908** | 75.746 | 76.239 |
| `prefix_scan` | 3.278 | 100.175 | **103.453** | 77.178 | 77.444 |
| `binary_search` | 3.406 | 99.265 | **102.671** | 75.535 | 79.279 |
| `sort_window` | 3.547 | 105.106 | **108.653** | 81.404 | 83.235 |
| `bloom_filter` | 3.693 | 103.127 | **106.820** | 80.610 | 79.254 |
| `hash_join` | 5.734 | 207.639 | **213.373** | 120.164 | 114.682 |
| `sieve` | 3.289 | 100.792 | **104.081** | 82.643 | 83.799 |
| `fib` | 3.051 | 92.308 | **95.359** | 72.323 | 71.197 |
| `collatz` | 3.220 | 96.986 | **100.206** | 73.713 | 74.649 |
| `matmul` | 3.527 | 103.278 | **106.805** | 84.163 | 97.913 |
| `json_parse` | 40.133 | 494.310 | **534.443** | 123.721 | 185.730 |
| `nbody` | 4.580 | 114.808 | **119.388** | 99.316 | 99.123 |

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
