# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-14T11:30:30Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `e28b3ca3812d0acc3f3156db44574ca6e45c0f44` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31796178744 |
| NURL | `v0.42.0-3-ge28b3ca3` |
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
| _(floor: empty program)_ | _1.744_ | _1.800_ | _1.946_ | _24.177_ | _18.228_ |
| `lcg` | 39.603 | **39.587** | 39.736 | 2055.946 | 5125.112 |
| `packet_classifier` | 56.767 | **56.752** | 56.906 | 162.938 | 4334.249 |
| `ring_write` | 42.869 | **42.755** | 42.899 | 68.799 | 6334.627 |
| `histogram_bins` | **40.016** | 41.696 | 40.186 | 67.290 | 6079.860 |
| `prefix_scan` | **22.135** | 22.238 | 22.421 | 67.260 | 4652.352 |
| `binary_search` | **36.683** | 38.542 | 43.580 | 108.040 | 5987.668 |
| `sort_window` | **27.040** | 27.710 | 27.258 | 199.023 | 11669.750 |
| `bloom_filter` | **18.258** | 18.501 | 18.785 | 2837.578 | 7625.837 |
| `hash_join` | **27.311** | 30.494 | 30.179 | 3418.814 | 8222.710 |
| `sieve` | 19.361 | **18.598** | 18.822 | 67.344 | 3448.765 |
| `fib` | **25.553** | 30.286 | 28.600 | 133.799 | 1358.572 |
| `collatz` | **12.631** | 12.650 | 12.798 | 50.075 | 714.080 |
| `matmul` | 34.114 | **34.025** | 34.248 | 76.515 | 3201.957 |
| `json_parse` | 9.373 | **9.059** | 12.042 | 37.768 | 39.076 |
| `nbody` | **25.692** | 41.363 | 39.449 | 102.415 | 2987.263 |

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
| _(floor: empty program)_ | _2.797_ | _95.355_ | _**98.152**_ | _61.587_ | _62.390_ | _64.106_ |
| `lcg` | 2.954 | 97.062 | **100.016** | 62.051 | 70.305 | 72.574 |
| `packet_classifier` | 3.055 | 97.014 | **100.069** | 61.237 | 71.266 | 71.281 |
| `ring_write` | 3.181 | 100.103 | **103.284** | 62.671 | 72.273 | 72.802 |
| `histogram_bins` | 3.323 | 124.197 | **127.520** | 64.288 | 73.842 | 77.017 |
| `prefix_scan` | 3.243 | 103.054 | **106.297** | 61.757 | 75.500 | 74.422 |
| `binary_search` | 3.317 | 107.675 | **110.992** | 61.460 | 72.734 | 78.279 |
| `sort_window` | 3.436 | 110.500 | **113.936** | 62.261 | 78.673 | 84.443 |
| `bloom_filter` | 3.701 | 106.800 | **110.501** | 61.944 | 79.869 | 78.207 |
| `hash_join` | 6.097 | 263.046 | **269.143** | 64.563 | 125.880 | 116.286 |
| `sieve` | 3.244 | 102.639 | **105.883** | 61.914 | 82.592 | 82.498 |
| `fib` | 3.022 | 96.825 | **99.847** | 61.756 | 69.151 | 72.767 |
| `collatz` | 3.165 | 99.972 | **103.137** | 62.886 | 71.898 | 72.386 |
| `matmul` | 3.470 | 105.415 | **108.885** | 62.856 | 84.148 | 96.016 |
| `json_parse` | 48.606 | 449.392 | **497.998** | 109.177 | 128.297 | 186.902 |
| `nbody` | 4.695 | 130.090 | **134.785** | 63.913 | 100.143 | 96.794 |

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
