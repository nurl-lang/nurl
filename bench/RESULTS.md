# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T16:40:47Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `4d5c56d5b17efa589442c29f89a2e8a8933eabae` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31959083917 |
| NURL | `v0.44.2` |
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
| _(floor: empty program)_ | _1.622_ | _1.665_ | _1.810_ | _21.664_ | _16.660_ |
| `lcg` | **39.088** | 39.251 | 39.330 | 2045.173 | 5188.433 |
| `packet_classifier` | **56.217** | 56.356 | 56.508 | 158.930 | 4437.047 |
| `ring_write` | **42.283** | 42.307 | 42.448 | 64.951 | 6660.571 |
| `histogram_bins` | **39.622** | 41.338 | 39.803 | 64.481 | 6011.086 |
| `prefix_scan` | **21.794** | 21.889 | 21.974 | 64.893 | 4502.549 |
| `binary_search` | **36.272** | 38.438 | 43.284 | 104.180 | 6882.658 |
| `sort_window` | **26.693** | 27.414 | 26.879 | 194.537 | 12386.695 |
| `bloom_filter` | **17.945** | 18.166 | 18.434 | 2828.562 | 7388.452 |
| `hash_join` | **27.170** | 30.144 | 29.904 | 3395.760 | 8292.785 |
| `sieve` | 18.657 | **17.945** | 18.063 | 63.699 | 3322.011 |
| `fib` | **25.296** | 30.035 | 28.244 | 129.581 | 1344.703 |
| `collatz` | **12.394** | 12.400 | 12.477 | 48.322 | 711.683 |
| `matmul` | 33.446 | **33.422** | 33.728 | 74.305 | 3097.186 |
| `json_parse` | 8.998 | **8.819** | 11.707 | 33.657 | 36.901 |
| `nbody` | **25.311** | 40.841 | 39.052 | 98.911 | 2982.575 |

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
| _(floor: empty program)_ | _2.768_ | _85.734_ | _**88.502**_ | _55.728_ | _54.971_ | _57.605_ |
| `lcg` | 2.900 | 87.257 | **90.157** | 55.736 | 63.718 | 65.174 |
| `packet_classifier` | 3.000 | 88.874 | **91.874** | 56.208 | 64.713 | 64.828 |
| `ring_write` | 3.084 | 90.117 | **93.201** | 56.187 | 65.644 | 67.941 |
| `histogram_bins` | 3.177 | 110.158 | **113.335** | 56.762 | 68.183 | 69.880 |
| `prefix_scan` | 3.228 | 94.035 | **97.263** | 56.812 | 69.561 | 69.029 |
| `binary_search` | 3.336 | 98.705 | **102.041** | 56.727 | 66.177 | 72.148 |
| `sort_window` | 3.421 | 101.918 | **105.339** | 56.723 | 72.545 | 76.775 |
| `bloom_filter` | 3.620 | 97.751 | **101.371** | 57.145 | 73.547 | 72.439 |
| `hash_join` | 6.033 | 247.826 | **253.859** | 59.596 | 117.158 | 107.688 |
| `sieve` | 3.231 | 93.077 | **96.308** | 56.207 | 75.449 | 75.948 |
| `fib` | 2.964 | 88.190 | **91.154** | 56.365 | 63.758 | 64.698 |
| `collatz` | 3.089 | 90.604 | **93.693** | 56.365 | 65.357 | 67.196 |
| `matmul` | 3.450 | 96.524 | **99.974** | 56.834 | 77.204 | 89.264 |
| `json_parse` | 50.153 | 422.441 | **472.594** | 105.553 | 119.662 | 172.079 |
| `nbody` | 4.708 | 120.131 | **124.839** | 58.162 | 93.267 | 89.652 |

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
