# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T22:32:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `e8b6fe6206044f01ce4695fa33254d4453a5c25b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31542554067 |
| NURL | `v0.38.0-12-ge8b6fe62` |
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
| _(floor: empty program)_ | _1.661_ | _1.723_ | _1.880_ | _24.635_ | _17.178_ |
| `lcg` | **39.207** | 39.283 | 39.403 | 1876.296 | 5066.549 |
| `packet_classifier` | **56.341** | 56.468 | 56.586 | 161.851 | 4414.217 |
| `ring_write` | **42.282** | 42.524 | 42.470 | 66.454 | 6224.319 |
| `histogram_bins` | **39.759** | 41.321 | 39.772 | 66.491 | 5997.203 |
| `prefix_scan` | **21.818** | 21.940 | 21.985 | 66.033 | 4702.028 |
| `binary_search` | 39.887 | **38.437** | 43.329 | 107.444 | 6690.587 |
| `sort_window` | 27.396 | 27.463 | **26.997** | 197.962 | 11610.226 |
| `bloom_filter` | **18.043** | 18.223 | 18.558 | 2826.550 | 7512.695 |
| `hash_join` | **27.926** | 30.142 | 30.089 | 3401.690 | 8346.220 |
| `sieve` | 20.936 | 18.700 | **18.612** | 68.272 | 3404.529 |
| `fib` | **25.325** | 30.067 | 28.453 | 131.726 | 1341.222 |
| `collatz` | **12.463** | 12.594 | 12.612 | 50.875 | 720.606 |
| `matmul` | 33.585 | **33.496** | 33.719 | 76.951 | 3064.921 |
| `json_parse` | 8.849 | **8.777** | 11.786 | 36.079 | 37.428 |
| `nbody` | 41.128 | 41.027 | **39.193** | 100.717 | 3070.025 |

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
| _(floor: empty program)_ | _2.855_ | _80.012_ | _**82.867**_ | _57.556_ | _61.137_ |
| `lcg` | 2.816 | 86.208 | **89.024** | 66.764 | 67.848 |
| `packet_classifier` | 2.899 | 87.013 | **89.912** | 67.072 | 67.878 |
| `ring_write` | 2.995 | 88.725 | **91.720** | 67.543 | 69.311 |
| `histogram_bins` | 3.067 | 91.800 | **94.867** | 70.355 | 71.587 |
| `prefix_scan` | 3.076 | 92.746 | **95.822** | 73.609 | 73.058 |
| `binary_search` | 3.258 | 91.219 | **94.477** | 70.458 | 75.522 |
| `sort_window` | 3.267 | 98.231 | **101.498** | 75.149 | 80.133 |
| `bloom_filter` | 3.422 | 97.430 | **100.852** | 76.639 | 76.097 |
| `hash_join` | 5.571 | 211.617 | **217.188** | 121.683 | 111.233 |
| `sieve` | 3.093 | 95.794 | **98.887** | 78.495 | 79.213 |
| `fib` | 2.887 | 89.123 | **92.010** | 68.526 | 68.272 |
| `collatz` | 3.064 | 93.167 | **96.231** | 71.249 | 74.361 |
| `matmul` | 3.394 | 101.139 | **104.533** | 83.479 | 94.527 |
| `json_parse` | 44.212 | 545.505 | **589.717** | 128.191 | 179.956 |
| `nbody` | 4.493 | 108.111 | **112.604** | 97.417 | 94.250 |

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
