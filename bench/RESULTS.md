# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T21:37:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `b82c52ce1c487a2250dcccb47de862d2c56826d6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31538362231 |
| NURL | `v0.38.0-9-gb82c52ce` |
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
| _(floor: empty program)_ | _1.841_ | _1.908_ | _2.043_ | _26.368_ | _18.674_ |
| `lcg` | **44.447** | 44.486 | 44.726 | 1842.188 | 5320.649 |
| `packet_classifier` | 63.760 | **63.748** | 64.019 | 157.006 | 4722.059 |
| `ring_write` | **47.928** | 48.069 | 48.251 | 73.660 | 6853.137 |
| `histogram_bins` | **44.857** | 44.922 | 45.025 | 74.890 | 6268.339 |
| `prefix_scan` | **24.692** | 24.772 | 24.957 | 72.486 | 4809.089 |
| `binary_search` | 36.067 | **35.904** | 46.276 | 112.264 | 6796.667 |
| `sort_window` | 30.913 | 31.112 | **30.514** | 166.157 | 12117.769 |
| `bloom_filter` | **19.937** | 20.579 | 20.931 | 2873.573 | 7651.029 |
| `hash_join` | **29.279** | 30.964 | 31.263 | 3361.640 | 8603.681 |
| `sieve` | **20.946** | 21.059 | 21.090 | 74.492 | 3454.957 |
| `fib` | **28.137** | 33.412 | 29.654 | 143.403 | 1287.336 |
| `collatz` | **14.056** | 14.157 | 14.225 | 53.721 | 751.852 |
| `matmul` | **45.628** | 45.971 | 46.453 | 85.283 | 4003.232 |
| `json_parse` | **8.830** | 9.294 | 12.602 | 39.535 | 39.356 |
| `nbody` | 46.466 | 46.605 | **44.411** | 98.710 | 3269.722 |

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
| _(floor: empty program)_ | _3.159_ | _92.199_ | _**95.358**_ | _66.761_ | _67.738_ |
| `lcg` | 3.213 | 96.844 | **100.057** | 73.829 | 74.999 |
| `packet_classifier` | 3.252 | 96.372 | **99.624** | 74.174 | 73.198 |
| `ring_write` | 3.345 | 97.345 | **100.690** | 74.886 | 77.367 |
| `histogram_bins` | 3.412 | 99.546 | **102.958** | 76.928 | 76.931 |
| `prefix_scan` | 3.496 | 104.587 | **108.083** | 81.372 | 78.232 |
| `binary_search` | 3.598 | 99.281 | **102.879** | 76.796 | 79.845 |
| `sort_window` | 3.673 | 110.017 | **113.690** | 83.474 | 83.184 |
| `bloom_filter` | 3.875 | 108.748 | **112.623** | 84.837 | 82.376 |
| `hash_join` | 6.036 | 215.502 | **221.538** | 125.580 | 118.514 |
| `sieve` | 3.535 | 104.232 | **107.767** | 83.792 | 86.107 |
| `fib` | 3.197 | 96.800 | **99.997** | 75.795 | 75.886 |
| `collatz` | 3.414 | 103.036 | **106.450** | 77.815 | 78.365 |
| `matmul` | 3.816 | 111.409 | **115.225** | 109.411 | 101.932 |
| `json_parse` | 44.147 | 525.777 | **569.924** | 129.642 | 192.624 |
| `nbody` | 4.893 | 120.007 | **124.900** | 103.076 | 103.141 |

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
