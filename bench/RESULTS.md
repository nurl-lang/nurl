# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-15T01:35:18Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `308bea47f89ca9500ce5077fc42af7442e4346ad` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31856687081 |
| NURL | `v0.42.0-17-g308bea47` |
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
| _(floor: empty program)_ | _1.719_ | _1.746_ | _1.888_ | _25.641_ | _18.128_ |
| `lcg` | **39.701** | 39.746 | 40.022 | 2060.286 | 5197.416 |
| `packet_classifier` | **56.655** | 56.981 | 57.214 | 164.744 | 4369.854 |
| `ring_write` | **42.709** | 42.871 | 43.020 | 68.228 | 6116.408 |
| `histogram_bins` | **40.056** | 41.799 | 40.247 | 69.028 | 6143.450 |
| `prefix_scan` | **22.284** | 22.395 | 22.568 | 68.842 | 4454.176 |
| `binary_search` | **36.787** | 39.109 | 43.855 | 110.300 | 6524.142 |
| `sort_window` | **27.137** | 28.043 | 27.383 | 199.585 | 24180.513 |
| `bloom_filter` | **18.390** | 18.584 | 18.916 | 2869.039 | 7427.525 |
| `hash_join` | **27.092** | 30.235 | 30.078 | 3504.187 | 8345.538 |
| `sieve` | 19.462 | 18.267 | **18.246** | 67.090 | 3224.474 |
| `fib` | **25.326** | 29.980 | 28.672 | 134.166 | 1372.023 |
| `collatz` | **12.440** | 12.643 | 12.717 | 52.201 | 720.558 |
| `matmul` | 34.157 | **33.924** | 34.066 | 80.401 | 3188.278 |
| `json_parse` | 9.236 | **8.922** | 11.837 | 37.761 | 38.091 |
| `nbody` | **25.734** | 41.357 | 39.620 | 102.895 | 3190.461 |

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
| _(floor: empty program)_ | _3.619_ | _102.176_ | _**105.795**_ | _65.826_ | _65.838_ | _64.425_ |
| `lcg` | 3.160 | 97.792 | **100.952** | 62.524 | 75.598 | 72.874 |
| `packet_classifier` | 3.011 | 96.004 | **99.015** | 60.450 | 73.647 | 72.135 |
| `ring_write` | 3.288 | 100.201 | **103.489** | 62.747 | 74.181 | 74.695 |
| `histogram_bins` | 3.364 | 121.470 | **124.834** | 62.939 | 76.506 | 76.825 |
| `prefix_scan` | 3.515 | 112.783 | **116.298** | 67.627 | 79.777 | 79.832 |
| `binary_search` | 3.441 | 108.187 | **111.628** | 65.021 | 74.840 | 81.705 |
| `sort_window` | 3.509 | 113.072 | **116.581** | 64.069 | 81.643 | 84.224 |
| `bloom_filter` | 4.032 | 110.641 | **114.673** | 65.864 | 83.880 | 82.717 |
| `hash_join` | 6.179 | 263.813 | **269.992** | 65.290 | 123.290 | 114.984 |
| `sieve` | 3.328 | 103.027 | **106.355** | 62.264 | 83.698 | 84.955 |
| `fib` | 3.004 | 95.287 | **98.291** | 59.727 | 68.630 | 73.399 |
| `collatz` | 3.504 | 105.733 | **109.237** | 65.360 | 72.614 | 73.640 |
| `matmul` | 3.481 | 103.194 | **106.675** | 60.820 | 87.695 | 99.420 |
| `json_parse` | 49.191 | 444.337 | **493.528** | 109.578 | 127.341 | 188.664 |
| `nbody` | 4.772 | 135.182 | **139.954** | 67.869 | 103.296 | 101.983 |

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
