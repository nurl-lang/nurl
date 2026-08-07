# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T12:42:02Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `13b93a4d900cbf01972476fc91a9b8c9ac8bcf2a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31178954990 |
| NURL | `v0.35.0` |
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
| _(floor: empty program)_ | _1.645_ | _1.702_ | _1.859_ | _22.278_ | _16.925_ |
| `lcg` | **39.162** | 39.181 | 39.332 | 1879.173 | 5248.713 |
| `packet_classifier` | **56.427** | 56.457 | 56.497 | 161.377 | 4390.635 |
| `ring_write` | **42.403** | 42.497 | 42.590 | 64.487 | 6286.425 |
| `histogram_bins` | **39.708** | 41.386 | 39.837 | 65.373 | 5929.277 |
| `prefix_scan` | **21.811** | 21.946 | 22.000 | 64.886 | 4891.767 |
| `binary_search` | 40.083 | **38.746** | 43.469 | 107.561 | 6360.286 |
| `sort_window` | 27.458 | 27.547 | **27.144** | 197.923 | 11494.372 |
| `bloom_filter` | **18.053** | 18.298 | 18.537 | 2837.178 | 7764.168 |
| `hash_join` | **28.057** | 30.177 | 29.991 | 3429.253 | 8215.279 |
| `sieve` | **20.049** | 20.169 | 20.052 | 66.456 | 3262.721 |
| `fib` | **25.234** | 30.020 | 28.282 | 130.178 | 1357.290 |
| `collatz` | **12.434** | 12.555 | 12.544 | 48.700 | 712.285 |
| `matmul` | 33.689 | **33.527** | 33.737 | 76.324 | 3221.265 |
| `json_parse` | **8.848** | 8.985 | 11.964 | 36.116 | 36.822 |
| `nbody` | 41.093 | 40.939 | **39.158** | 99.341 | 3091.243 |

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
| _(floor: empty program)_ | _2.568_ | _77.809_ | _**80.377**_ | _56.223_ | _60.257_ |
| `lcg` | 2.679 | 85.694 | **88.373** | 65.346 | 68.309 |
| `packet_classifier` | 2.775 | 85.595 | **88.370** | 65.339 | 67.607 |
| `ring_write` | 2.879 | 85.346 | **88.225** | 66.095 | 69.246 |
| `histogram_bins` | 2.901 | 88.702 | **91.603** | 68.648 | 72.356 |
| `prefix_scan` | 2.949 | 90.717 | **93.666** | 70.223 | 70.996 |
| `binary_search` | 3.122 | 93.105 | **96.227** | 68.258 | 75.658 |
| `sort_window` | 3.174 | 100.178 | **103.352** | 77.746 | 80.648 |
| `bloom_filter` | 3.317 | 97.349 | **100.666** | 75.974 | 74.179 |
| `hash_join` | 5.206 | 206.951 | **212.157** | 116.790 | 109.332 |
| `sieve` | 2.954 | 90.295 | **93.249** | 76.075 | 78.561 |
| `fib` | 2.738 | 82.387 | **85.125** | 65.141 | 67.090 |
| `collatz` | 2.860 | 87.914 | **90.774** | 67.176 | 69.270 |
| `matmul` | 3.163 | 96.016 | **99.179** | 78.579 | 90.469 |
| `json_parse` | 38.808 | 507.945 | **546.753** | 120.206 | 176.468 |
| `nbody` | 4.142 | 105.918 | **110.060** | 96.489 | 92.104 |

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
