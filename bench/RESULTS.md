# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T23:48:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `7d052f3061caeff95c1b7737f8aca1b528d3c612` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31228043627 |
| NURL | `v0.35.1-10-g7d052f30` |
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
| _(floor: empty program)_ | _1.402_ | _1.389_ | _1.482_ | _21.392_ | _15.702_ |
| `lcg` | **39.292** | 41.247 | 39.320 | 1446.709 | 4195.976 |
| `packet_classifier` | **61.688** | 67.253 | 63.037 | 155.876 | 3341.063 |
| `ring_write` | 41.944 | 41.596 | **41.401** | 61.701 | 4877.826 |
| `histogram_bins` | 39.083 | **38.513** | 39.458 | 62.195 | 4570.433 |
| `prefix_scan` | **20.642** | 21.024 | 20.978 | 59.881 | 3435.900 |
| `binary_search` | 32.295 | **30.627** | 43.728 | 106.255 | 5256.732 |
| `sort_window` | 39.308 | 49.062 | **38.286** | 169.551 | 8529.130 |
| `bloom_filter` | 13.861 | **13.210** | 13.680 | 2207.154 | 6185.494 |
| `hash_join` | **22.643** | 24.086 | 25.625 | 2777.516 | 6429.462 |
| `sieve` | 32.846 | 32.635 | **32.435** | 77.084 | 2455.373 |
| `fib` | 26.717 | 27.874 | **23.357** | 102.228 | 813.387 |
| `collatz` | **13.378** | 14.301 | 14.316 | 54.679 | 519.572 |
| `matmul` | 18.087 | **17.899** | 18.215 | 65.804 | 2289.075 |
| `json_parse` | 32.015 | **6.696** | 8.520 | 29.714 | 29.997 |
| `nbody` | 30.711 | 29.910 | **27.090** | 74.236 | 1935.553 |

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
| _(floor: empty program)_ | _2.209_ | _67.738_ | _**69.947**_ | _47.249_ | _56.902_ |
| `lcg` | 2.354 | 73.391 | **75.745** | 54.955 | 64.472 |
| `packet_classifier` | 2.405 | 75.912 | **78.317** | 57.464 | 62.898 |
| `ring_write` | 2.449 | 71.708 | **74.157** | 57.321 | 64.322 |
| `histogram_bins` | 2.427 | 72.873 | **75.300** | 56.371 | 63.070 |
| `prefix_scan` | 2.476 | 75.055 | **77.531** | 56.571 | 61.848 |
| `binary_search` | 2.594 | 73.486 | **76.080** | 53.656 | 67.121 |
| `sort_window` | 2.652 | 81.460 | **84.112** | 64.032 | 82.910 |
| `bloom_filter` | 2.754 | 80.292 | **83.046** | 60.970 | 66.892 |
| `hash_join` | 4.618 | 171.114 | **175.732** | 97.498 | 101.048 |
| `sieve` | 2.377 | 73.823 | **76.200** | 60.473 | 71.077 |
| `fib` | 2.295 | 67.108 | **69.403** | 52.936 | 59.565 |
| `collatz` | 2.507 | 73.779 | **76.286** | 52.723 | 61.037 |
| `matmul` | 2.716 | 78.037 | **80.753** | 65.032 | 84.340 |
| `json_parse` | 34.197 | 424.525 | **458.722** | 95.594 | 165.093 |
| `nbody` | 3.305 | 85.570 | **88.875** | 75.945 | 81.477 |

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
