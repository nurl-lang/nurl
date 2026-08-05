# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T05:02:51Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0329e85ff58a8fc04a96fa5ccb89f53ae5c8f1ec` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30976668129 |
| NURL | `v0.33.0` |
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
| _(floor: empty program)_ | _1.670_ | _1.718_ | _1.897_ | _22.446_ | _16.836_ |
| `lcg` | **39.316** | 39.400 | 39.416 | 1867.142 | 5044.800 |
| `packet_classifier` | **56.538** | 56.669 | 56.836 | 163.178 | 4361.178 |
| `ring_write` | **42.296** | 42.348 | 42.504 | 65.456 | 6139.614 |
| `histogram_bins` | **39.649** | 41.318 | 39.804 | 66.154 | 6344.857 |
| `prefix_scan` | **21.908** | 21.986 | 22.123 | 64.652 | 4419.583 |
| `binary_search` | 40.032 | **38.408** | 43.348 | 106.668 | 6271.219 |
| `sort_window` | 27.335 | 27.439 | **26.895** | 198.495 | 11277.419 |
| `bloom_filter` | **17.963** | 18.207 | 18.491 | 2847.092 | 7578.262 |
| `hash_join` | **28.112** | 30.329 | 30.107 | 3418.243 | 8216.012 |
| `sieve` | 19.334 | 18.997 | **18.494** | 68.101 | 3294.729 |
| `fib` | **25.227** | 30.129 | 28.335 | 130.125 | 1373.544 |
| `collatz` | **12.453** | 12.470 | 12.587 | 49.469 | 713.717 |
| `matmul` | 33.633 | **33.614** | 33.756 | 75.608 | 3139.483 |
| `json_parse` | **8.844** | 8.952 | 11.847 | 36.822 | 37.747 |
| `nbody` | 41.101 | 41.131 | **39.202** | 102.161 | 3070.360 |

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
| _(floor: empty program)_ | _2.671_ | _81.051_ | _**83.722**_ | _62.035_ | _61.549_ |
| `lcg` | 2.735 | 85.595 | **88.330** | 66.249 | 68.357 |
| `packet_classifier` | 2.801 | 87.079 | **89.880** | 66.212 | 67.303 |
| `ring_write` | 2.967 | 89.376 | **92.343** | 68.099 | 68.992 |
| `histogram_bins` | 2.932 | 91.948 | **94.880** | 70.546 | 71.416 |
| `prefix_scan` | 2.989 | 93.140 | **96.129** | 72.610 | 71.484 |
| `binary_search` | 3.092 | 90.989 | **94.081** | 68.580 | 74.412 |
| `sort_window` | 3.216 | 103.502 | **106.718** | 75.293 | 80.884 |
| `bloom_filter` | 3.337 | 97.880 | **101.217** | 77.107 | 76.282 |
| `hash_join` | 5.369 | 214.392 | **219.761** | 120.921 | 111.641 |
| `sieve` | 3.010 | 95.753 | **98.763** | 80.579 | 81.572 |
| `fib` | 2.733 | 85.906 | **88.639** | 66.126 | 66.941 |
| `collatz` | 2.921 | 90.278 | **93.199** | 67.629 | 69.760 |
| `matmul` | 3.188 | 96.830 | **100.018** | 80.547 | 91.975 |
| `json_parse` | 40.346 | 528.464 | **568.810** | 126.327 | 179.893 |
| `nbody` | 4.296 | 110.939 | **115.235** | 98.995 | 93.893 |

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
