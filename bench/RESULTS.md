# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T05:48:26Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3ba5a37a5c95cd7d56c1b2424e113cc81b7fc858` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32336709057 |
| NURL | `v0.45.0-17-g3ba5a37a` |
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
| _(floor: empty program)_ | _1.713_ | _1.716_ | _1.926_ | _23.092_ | _17.976_ |
| `lcg` | **39.432** | 39.490 | 39.517 | 2087.745 | 5283.903 |
| `packet_classifier` | 56.544 | **56.542** | 56.731 | 162.700 | 4345.992 |
| `ring_write` | **42.445** | 42.576 | 42.695 | 67.405 | 6067.379 |
| `histogram_bins` | **39.842** | 41.603 | 39.961 | 66.566 | 6123.707 |
| `prefix_scan` | **22.163** | 22.184 | 22.310 | 66.907 | 4590.914 |
| `binary_search` | **36.421** | 38.538 | 43.408 | 107.439 | 6147.174 |
| `sort_window` | **26.831** | 27.539 | 27.128 | 197.469 | 11357.326 |
| `bloom_filter` | **18.144** | 18.276 | 18.541 | 2849.759 | 7399.943 |
| `hash_join` | **27.141** | 30.341 | 30.134 | 3438.354 | 8291.127 |
| `sieve` | **18.604** | 20.913 | 20.651 | 67.258 | 3279.452 |
| `fib` | **25.435** | 30.185 | 28.390 | 132.087 | 1352.689 |
| `collatz` | 12.551 | **12.529** | 12.689 | 50.249 | 712.837 |
| `matmul` | 33.879 | **33.869** | 34.160 | 77.633 | 3051.610 |
| `json_parse` | 9.226 | **8.865** | 11.887 | 36.036 | 38.346 |
| `nbody` | **25.375** | 41.050 | 39.312 | 102.099 | 3118.039 |

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
| _(floor: empty program)_ | _2.891_ | _97.188_ | _**100.079**_ | _59.700_ | _58.838_ | _60.237_ |
| `lcg` | 3.053 | 96.386 | **99.439** | 58.355 | 68.571 | 69.113 |
| `packet_classifier` | 3.123 | 99.015 | **102.138** | 60.107 | 72.375 | 68.995 |
| `ring_write` | 3.164 | 97.822 | **100.986** | 59.548 | 71.288 | 69.530 |
| `histogram_bins` | 3.283 | 114.948 | **118.231** | 60.387 | 72.071 | 71.862 |
| `prefix_scan` | 3.314 | 101.803 | **105.117** | 60.558 | 76.023 | 73.066 |
| `binary_search` | 3.467 | 106.305 | **109.772** | 61.223 | 72.314 | 76.145 |
| `sort_window` | 3.591 | 107.727 | **111.318** | 59.627 | 78.303 | 81.725 |
| `bloom_filter` | 3.815 | 105.188 | **109.003** | 61.050 | 79.528 | 75.632 |
| `hash_join` | 6.353 | 256.016 | **262.369** | 63.428 | 122.547 | 113.988 |
| `sieve` | 3.411 | 99.716 | **103.127** | 59.700 | 80.793 | 80.818 |
| `fib` | 3.194 | 96.629 | **99.823** | 59.941 | 68.738 | 68.111 |
| `collatz` | 3.249 | 100.435 | **103.684** | 60.318 | 71.712 | 71.422 |
| `matmul` | 3.645 | 103.653 | **107.298** | 61.022 | 84.088 | 93.827 |
| `json_parse` | 53.306 | 437.327 | **490.633** | 112.132 | 126.662 | 181.316 |
| `nbody` | 4.964 | 128.651 | **133.615** | 62.510 | 99.970 | 93.442 |

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
