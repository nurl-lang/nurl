# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-03T13:01:31Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `db2e7fd7936aca43c9dbc8f6cbaab255beec8b25` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30815698683 |
| NURL | `v0.32.0-7-gdb2e7fd7` |
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
| _(floor: empty program)_ | _1.841_ | _1.915_ | _2.019_ | _25.016_ | _17.883_ |
| `lcg` | **44.304** | 44.383 | 44.480 | 1830.098 | 5440.158 |
| `packet_classifier` | **63.751** | 63.775 | 63.947 | 158.694 | 4616.465 |
| `ring_write` | **47.855** | 47.928 | 48.079 | 73.419 | 6833.083 |
| `histogram_bins` | **44.701** | 44.895 | 45.057 | 74.507 | 6332.853 |
| `prefix_scan` | **24.651** | 24.721 | 24.880 | 71.042 | 4656.333 |
| `binary_search` | **35.806** | 36.010 | 46.150 | 111.468 | 6924.940 |
| `sort_window` | 30.948 | 30.917 | **30.429** | 164.538 | 10981.267 |
| `bloom_filter` | **20.027** | 20.614 | 20.816 | 2804.127 | 8150.892 |
| `hash_join` | **30.336** | 30.913 | 31.465 | 3472.917 | 8124.960 |
| `sieve` | 20.602 | **20.211** | 20.663 | 70.435 | 3439.921 |
| `fib` | **28.072** | 33.517 | 29.588 | 142.363 | 1294.998 |
| `collatz` | **13.925** | 14.087 | 14.349 | 53.016 | 753.896 |
| `matmul` | **45.963** | 46.331 | 46.846 | 83.976 | 3539.214 |
| `json_parse` | **8.503** | 9.081 | 12.423 | 37.269 | 38.214 |
| `nbody` | 46.316 | 46.370 | **44.288** | 95.301 | 3341.830 |

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
| _(floor: empty program)_ | _2.957_ | _84.948_ | _**87.905**_ | _63.207_ | _65.264_ |
| `lcg` | 2.991 | 91.120 | **94.111** | 71.408 | 73.217 |
| `packet_classifier` | 3.136 | 92.898 | **96.034** | 72.572 | 72.666 |
| `ring_write` | 3.252 | 99.253 | **102.505** | 73.966 | 74.804 |
| `histogram_bins` | 3.285 | 96.174 | **99.459** | 75.305 | 76.975 |
| `prefix_scan` | 3.288 | 98.732 | **102.020** | 77.375 | 76.396 |
| `binary_search` | 3.444 | 96.725 | **100.169** | 74.542 | 82.425 |
| `sort_window` | 3.505 | 103.674 | **107.179** | 80.894 | 83.240 |
| `bloom_filter` | 3.698 | 101.885 | **105.583** | 80.662 | 79.667 |
| `hash_join` | 5.716 | 207.570 | **213.286** | 121.465 | 115.156 |
| `sieve` | 3.410 | 102.718 | **106.128** | 86.959 | 86.021 |
| `fib` | 3.080 | 91.924 | **95.004** | 73.526 | 72.179 |
| `collatz` | 3.294 | 98.243 | **101.537** | 77.142 | 76.031 |
| `matmul` | 3.595 | 107.288 | **110.883** | 87.255 | 98.896 |
| `json_parse` | 40.078 | 499.503 | **539.581** | 127.631 | 188.728 |
| `nbody` | 4.567 | 113.662 | **118.229** | 100.237 | 99.325 |

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
