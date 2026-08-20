# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T09:51:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `766f5b22ecedb25135dff7a1f939202996bd6c75` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32355598069 |
| NURL | `v0.46.0` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
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
| _(floor: empty program)_ | _1.827_ | _1.861_ | _2.059_ | _25.855_ | _18.903_ |
| `lcg` | **44.501** | 44.528 | 44.665 | 1822.315 | 5545.052 |
| `packet_classifier` | **63.897** | 63.920 | 64.155 | 159.429 | 4752.155 |
| `ring_write` | 48.115 | **48.044** | 48.248 | 73.989 | 6674.333 |
| `histogram_bins` | **44.962** | 45.167 | 45.101 | 75.148 | 6187.087 |
| `prefix_scan` | **24.745** | 24.839 | 25.062 | 72.887 | 4624.748 |
| `binary_search` | **34.598** | 36.117 | 46.345 | 112.495 | 7344.780 |
| `sort_window` | **30.189** | 31.049 | 30.382 | 165.464 | 10912.858 |
| `bloom_filter` | **20.048** | 20.674 | 20.954 | 2795.088 | 7697.601 |
| `hash_join` | **27.952** | 31.164 | 31.417 | 3544.412 | 8104.602 |
| `sieve` | 20.846 | **20.456** | 20.673 | 70.831 | 3454.877 |
| `fib` | **28.055** | 33.491 | 29.535 | 144.597 | 1291.368 |
| `collatz` | **13.877** | 13.995 | 14.080 | 53.101 | 751.640 |
| `matmul` | 46.348 | 46.510 | **46.176** | 83.807 | 3684.257 |
| `json_parse` | **9.086** | 9.135 | 12.343 | 39.667 | 38.701 |
| `nbody` | **27.028** | 46.432 | 44.348 | 96.185 | 3289.676 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns: a cold compile, measured
against a wiped cache exactly as C and Rust pay their full cost every
time. **NURL rebuild** is the same compile again with the ThinLTO
cache warm — `nurl.sh`'s default on Linux (docs/BUILDING.md → The
ThinLTO cache) — which is what every build after the first costs; C
and Rust have no default equivalent (`ccache`/`sccache` are opt-in
add-ons). The floor row is what each toolchain costs for a program
that does nothing — for NURL that is dominated by the LTO link every
NURL binary pays for, so subtract it to read the marginal cost of the
benchmark itself. Node and Python have no column here: they compile
at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | NURL rebuild | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.295_ | _109.799_ | _**113.094**_ | _67.333_ | _68.364_ | _93.528_ |
| `lcg` | 3.415 | 106.143 | **109.558** | 66.625 | 75.692 | 75.297 |
| `packet_classifier` | 3.438 | 107.215 | **110.653** | 66.771 | 78.085 | 75.269 |
| `ring_write` | 3.671 | 110.552 | **114.223** | 68.649 | 80.114 | 78.984 |
| `histogram_bins` | 3.667 | 128.276 | **131.943** | 67.509 | 80.384 | 80.119 |
| `prefix_scan` | 3.720 | 110.790 | **114.510** | 66.903 | 82.157 | 80.006 |
| `binary_search` | 3.936 | 116.903 | **120.839** | 67.754 | 79.869 | 83.620 |
| `sort_window` | 4.093 | 119.829 | **123.922** | 68.464 | 86.400 | 87.720 |
| `bloom_filter` | 4.125 | 113.448 | **117.573** | 67.072 | 85.160 | 82.096 |
| `hash_join` | 6.786 | 257.914 | **264.700** | 70.040 | 124.472 | 116.178 |
| `sieve` | 3.679 | 108.924 | **112.603** | 65.929 | 86.172 | 85.934 |
| `fib` | 3.442 | 105.680 | **109.122** | 66.555 | 75.699 | 73.565 |
| `collatz` | 3.575 | 107.250 | **110.825** | 65.787 | 76.401 | 77.615 |
| `matmul` | 4.048 | 112.529 | **116.577** | 67.656 | 88.864 | 100.543 |
| `json_parse` | 52.733 | 422.086 | **474.819** | 116.333 | 129.337 | 191.406 |
| `nbody` | 5.345 | 135.988 | **141.333** | 67.548 | 103.728 | 102.530 |

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
