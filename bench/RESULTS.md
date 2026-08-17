# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-17T19:33:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `0329a9ebacfe9f1aeabdb293c5e5d40cefbfb349` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32060657435 |
| NURL | `v0.44.2-20-g0329a9eb` |
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
| _(floor: empty program)_ | _1.212_ | _1.263_ | _1.346_ | _18.832_ | _13.534_ |
| `lcg` | 35.969 | **35.927** | 36.493 | 1420.541 | 3988.885 |
| `packet_classifier` | **61.134** | 63.386 | 61.164 | 150.420 | 3175.841 |
| `ring_write` | 39.170 | 39.967 | **39.115** | 60.012 | 4793.692 |
| `histogram_bins` | **36.233** | 36.264 | 37.153 | 62.201 | 4379.555 |
| `prefix_scan` | **19.312** | 19.712 | 20.037 | 59.890 | 3331.702 |
| `binary_search` | **23.882** | 28.886 | 40.455 | 99.578 | 4733.361 |
| `sort_window` | **34.897** | 46.688 | 36.127 | 160.783 | 8310.526 |
| `bloom_filter` | 13.106 | 14.415 | **12.776** | 2247.078 | 5980.191 |
| `hash_join` | **21.232** | 23.298 | 23.683 | 2755.119 | 6486.908 |
| `sieve` | 33.175 | **33.137** | 33.461 | 76.548 | 2406.528 |
| `fib` | 25.730 | 26.526 | **22.999** | 101.248 | 813.815 |
| `collatz` | **13.389** | 13.474 | 14.951 | 55.104 | 525.948 |
| `matmul` | 18.236 | **17.905** | 18.403 | 68.934 | 2314.904 |
| `json_parse` | **6.700** | 6.716 | 8.466 | 27.514 | 30.416 |
| `nbody` | **19.753** | 28.286 | 26.234 | 72.850 | 1922.995 |

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
| _(floor: empty program)_ | _2.219_ | _63.256_ | _**65.475**_ | _42.559_ | _39.774_ | _49.457_ |
| `lcg` | 2.296 | 64.033 | **66.329** | 40.792 | 49.951 | 56.244 |
| `packet_classifier` | 2.395 | 66.701 | **69.096** | 41.043 | 45.662 | 56.602 |
| `ring_write` | 2.411 | 70.127 | **72.538** | 40.327 | 47.394 | 57.047 |
| `histogram_bins` | 2.471 | 78.855 | **81.326** | 39.228 | 48.945 | 59.147 |
| `prefix_scan` | 2.566 | 68.959 | **71.525** | 42.054 | 47.848 | 60.233 |
| `binary_search` | 2.688 | 73.802 | **76.490** | 40.838 | 49.228 | 60.946 |
| `sort_window` | 2.864 | 78.539 | **81.403** | 43.320 | 54.900 | 67.296 |
| `bloom_filter` | 2.887 | 74.045 | **76.932** | 41.042 | 52.846 | 62.076 |
| `hash_join` | 4.905 | 194.170 | **199.075** | 46.486 | 86.428 | 93.872 |
| `sieve` | 2.779 | 72.706 | **75.485** | 42.539 | 57.839 | 67.320 |
| `fib` | 2.395 | 70.889 | **73.284** | 40.733 | 54.585 | 56.813 |
| `collatz` | 2.599 | 71.848 | **74.447** | 43.848 | 50.906 | 61.527 |
| `matmul` | 2.810 | 80.682 | **83.492** | 45.372 | 62.196 | 83.058 |
| `json_parse` | 42.632 | 338.386 | **381.018** | 87.477 | 93.419 | 162.354 |
| `nbody` | 3.705 | 92.738 | **96.443** | 44.806 | 71.019 | 81.318 |

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
