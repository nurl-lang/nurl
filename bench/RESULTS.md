# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-10T17:36:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `7843c579164768b11a7531aaaa0569ea40a88fd0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31414499083 |
| NURL | `v0.36.0-61-g7843c579` |
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
| _(floor: empty program)_ | _1.825_ | _1.893_ | _2.062_ | _24.860_ | _18.624_ |
| `lcg` | **44.561** | 44.577 | 44.674 | 1839.006 | 5301.996 |
| `packet_classifier` | **63.806** | 63.920 | 64.131 | 157.575 | 5074.480 |
| `ring_write` | **47.928** | 47.978 | 48.134 | 74.285 | 6701.289 |
| `histogram_bins` | **44.996** | 45.012 | 45.168 | 76.562 | 6217.736 |
| `prefix_scan` | **24.932** | 25.011 | 25.097 | 73.261 | 4869.638 |
| `binary_search` | **35.830** | 36.213 | 46.345 | 112.910 | 6991.984 |
| `sort_window` | 31.082 | 31.208 | **30.624** | 170.389 | 11374.430 |
| `bloom_filter` | **20.020** | 20.636 | 21.010 | 2765.481 | 7936.816 |
| `hash_join` | **29.542** | 31.191 | 31.467 | 3368.430 | 8479.988 |
| `sieve` | 21.029 | **20.727** | 20.859 | 74.508 | 3551.738 |
| `fib` | **28.462** | 33.685 | 29.772 | 143.556 | 1295.332 |
| `collatz` | **13.983** | 14.091 | 14.201 | 53.634 | 757.624 |
| `matmul` | **45.695** | 46.167 | 46.347 | 86.293 | 3337.869 |
| `json_parse` | 45.867 | **9.231** | 12.531 | 40.050 | 39.044 |
| `nbody` | 46.434 | 46.493 | **44.323** | 97.089 | 3246.946 |

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
| _(floor: empty program)_ | _3.070_ | _93.746_ | _**96.816**_ | _67.591_ | _69.395_ |
| `lcg` | 3.139 | 99.505 | **102.644** | 76.973 | 77.020 |
| `packet_classifier` | 3.244 | 99.625 | **102.869** | 76.544 | 75.854 |
| `ring_write` | 3.323 | 101.854 | **105.177** | 77.775 | 77.827 |
| `histogram_bins` | 3.422 | 103.042 | **106.464** | 80.101 | 79.373 |
| `prefix_scan` | 3.549 | 109.528 | **113.077** | 84.844 | 84.456 |
| `binary_search` | 3.582 | 104.161 | **107.743** | 79.248 | 83.201 |
| `sort_window` | 3.621 | 111.529 | **115.150** | 85.466 | 88.065 |
| `bloom_filter` | 3.845 | 110.293 | **114.138** | 86.920 | 84.727 |
| `hash_join` | 6.046 | 216.189 | **222.235** | 127.260 | 119.177 |
| `sieve` | 3.466 | 105.876 | **109.342** | 87.147 | 88.828 |
| `fib` | 3.200 | 99.123 | **102.323** | 76.598 | 76.178 |
| `collatz` | 3.372 | 104.263 | **107.635** | 77.283 | 79.682 |
| `matmul` | 3.732 | 109.275 | **113.007** | 88.719 | 101.127 |
| `json_parse` | 42.306 | 526.001 | **568.307** | 128.020 | 191.505 |
| `nbody` | 4.778 | 120.815 | **125.593** | 104.104 | 102.194 |

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
