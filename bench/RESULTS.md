# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T19:53:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `f838e07ebe1e5d70e6e692d4a5216cebbdbcd68b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31213109270 |
| NURL | `v0.35.0-10-gf838e07e` |
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
| _(floor: empty program)_ | _1.820_ | _1.905_ | _2.008_ | _25.884_ | _18.859_ |
| `lcg` | **44.240** | 44.326 | 44.534 | 1848.649 | 5436.580 |
| `packet_classifier` | **63.617** | 63.779 | 63.908 | 157.723 | 4768.491 |
| `ring_write` | **47.801** | 47.846 | 47.976 | 73.047 | 6552.466 |
| `histogram_bins` | 45.058 | 44.976 | **44.957** | 74.455 | 6278.300 |
| `prefix_scan` | **24.657** | 24.710 | 24.851 | 72.155 | 4709.753 |
| `binary_search` | 36.073 | **35.925** | 46.248 | 113.813 | 6612.866 |
| `sort_window` | 30.934 | 30.995 | **30.464** | 165.860 | 12569.072 |
| `bloom_filter` | **19.863** | 20.626 | 20.831 | 2807.564 | 8197.458 |
| `hash_join` | **29.446** | 30.992 | 31.315 | 3411.889 | 8211.995 |
| `sieve` | 20.746 | 20.719 | **20.682** | 71.260 | 3578.786 |
| `fib` | **28.114** | 33.425 | 29.580 | 142.353 | 1282.926 |
| `collatz` | 13.939 | **13.919** | 14.055 | 53.657 | 754.357 |
| `matmul` | **45.783** | 46.576 | 46.182 | 84.203 | 3853.882 |
| `json_parse` | **8.673** | 9.163 | 12.421 | 40.858 | 37.952 |
| `nbody` | 46.373 | 46.451 | **44.929** | 98.175 | 3340.298 |

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
| _(floor: empty program)_ | _3.033_ | _94.002_ | _**97.035**_ | _67.898_ | _66.493_ |
| `lcg` | 3.108 | 97.786 | **100.894** | 80.225 | 73.120 |
| `packet_classifier` | 3.120 | 95.512 | **98.632** | 73.016 | 72.520 |
| `ring_write` | 3.266 | 95.566 | **98.832** | 74.214 | 73.801 |
| `histogram_bins` | 3.384 | 104.329 | **107.713** | 76.854 | 78.677 |
| `prefix_scan` | 3.379 | 105.876 | **109.255** | 81.511 | 76.508 |
| `binary_search` | 3.494 | 102.300 | **105.794** | 76.598 | 79.912 |
| `sort_window` | 3.598 | 111.066 | **114.664** | 85.911 | 84.625 |
| `bloom_filter` | 3.769 | 106.711 | **110.480** | 85.128 | 109.705 |
| `hash_join` | 5.701 | 213.005 | **218.706** | 124.229 | 115.753 |
| `sieve` | 3.309 | 102.133 | **105.442** | 83.786 | 85.489 |
| `fib` | 3.072 | 93.017 | **96.089** | 72.658 | 72.129 |
| `collatz` | 3.222 | 97.951 | **101.173** | 75.226 | 76.327 |
| `matmul` | 3.575 | 104.847 | **108.422** | 85.766 | 98.016 |
| `json_parse` | 40.592 | 500.853 | **541.445** | 127.825 | 189.375 |
| `nbody` | 4.642 | 121.146 | **125.788** | 101.241 | 99.794 |

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
