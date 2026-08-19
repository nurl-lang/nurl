# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-19T14:44:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377732 KiB |
| Commit | `dc8d1c757e212046a56e17c36402354130e0ceee` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32265322400 |
| NURL | `v0.45.0-7-gdc8d1c75` |
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
| _(floor: empty program)_ | _1.658_ | _1.704_ | _1.824_ | _21.323_ | _16.694_ |
| `lcg` | **39.189** | 39.317 | 39.450 | 2041.118 | 5287.891 |
| `packet_classifier` | **56.355** | 56.440 | 56.579 | 160.294 | 4621.877 |
| `ring_write` | **42.628** | 42.728 | 42.800 | 68.432 | 6284.586 |
| `histogram_bins` | **39.675** | 41.334 | 40.052 | 66.648 | 6238.290 |
| `prefix_scan` | 21.927 | **21.908** | 22.032 | 64.328 | 4639.853 |
| `binary_search` | **36.399** | 38.526 | 43.367 | 104.813 | 5976.564 |
| `sort_window` | **26.910** | 27.848 | 26.957 | 197.413 | 11672.880 |
| `bloom_filter` | **18.179** | 18.494 | 18.667 | 2839.983 | 7779.975 |
| `hash_join` | **27.261** | 30.349 | 30.052 | 3436.083 | 8256.467 |
| `sieve` | 19.090 | 20.504 | **18.716** | 67.321 | 3338.882 |
| `fib` | **25.373** | 30.091 | 28.285 | 131.210 | 1362.303 |
| `collatz` | **12.508** | 12.513 | 12.553 | 48.799 | 718.099 |
| `matmul` | **33.587** | 34.702 | 34.019 | 76.552 | 3108.698 |
| `json_parse` | 9.105 | **8.793** | 11.676 | 35.075 | 37.338 |
| `nbody` | **25.326** | 40.921 | 39.110 | 100.567 | 3052.634 |

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
| _(floor: empty program)_ | _2.839_ | _88.535_ | _**91.374**_ | _56.737_ | _55.226_ | _59.638_ |
| `lcg` | 2.985 | 89.788 | **92.773** | 55.506 | 63.754 | 67.003 |
| `packet_classifier` | 3.069 | 92.822 | **95.891** | 57.045 | 69.757 | 71.725 |
| `ring_write` | 3.211 | 95.994 | **99.205** | 58.826 | 69.766 | 72.301 |
| `histogram_bins` | 3.235 | 112.413 | **115.648** | 58.605 | 70.658 | 72.467 |
| `prefix_scan` | 3.375 | 102.743 | **106.118** | 60.641 | 74.229 | 75.429 |
| `binary_search` | 3.429 | 103.251 | **106.680** | 58.660 | 68.160 | 73.809 |
| `sort_window` | 3.495 | 104.270 | **107.765** | 58.690 | 79.377 | 79.601 |
| `bloom_filter` | 3.783 | 105.265 | **109.048** | 61.011 | 78.824 | 75.694 |
| `hash_join` | 6.222 | 251.710 | **257.932** | 61.339 | 120.353 | 111.503 |
| `sieve` | 3.375 | 97.461 | **100.836** | 58.192 | 79.543 | 79.044 |
| `fib` | 3.036 | 94.801 | **97.837** | 57.923 | 66.481 | 66.756 |
| `collatz` | 3.244 | 96.351 | **99.595** | 60.583 | 70.148 | 72.729 |
| `matmul` | 3.614 | 100.013 | **103.627** | 58.638 | 80.162 | 91.382 |
| `json_parse` | 52.870 | 427.313 | **480.183** | 110.566 | 123.227 | 177.419 |
| `nbody` | 4.937 | 123.903 | **128.840** | 59.919 | 95.167 | 92.147 |

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
