# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T21:02:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `89abe5502ab63f9c108783108386a4e96c592a70` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31743440178 |
| NURL | `v0.40.0-13-g89abe550` |
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
| _(floor: empty program)_ | _1.827_ | _1.849_ | _2.056_ | _24.587_ | _18.024_ |
| `lcg` | **44.380** | 44.389 | 45.210 | 1820.032 | 5350.955 |
| `packet_classifier` | **63.744** | 63.855 | 63.954 | 158.644 | 4680.209 |
| `ring_write` | 48.015 | **47.938** | 48.124 | 72.860 | 6767.638 |
| `histogram_bins` | **44.762** | 44.879 | 44.938 | 75.075 | 6505.202 |
| `prefix_scan` | **24.688** | 24.757 | 24.901 | 70.147 | 4670.079 |
| `binary_search` | **34.443** | 36.009 | 46.082 | 110.928 | 7787.559 |
| `sort_window` | **30.208** | 30.962 | 30.408 | 164.624 | 11760.297 |
| `bloom_filter` | **19.908** | 20.532 | 20.818 | 2725.162 | 7809.014 |
| `hash_join` | **27.907** | 30.878 | 31.295 | 3482.506 | 8276.855 |
| `sieve` | **20.412** | 20.602 | 20.623 | 70.729 | 3458.915 |
| `fib` | **28.194** | 33.545 | 29.531 | 142.657 | 1288.060 |
| `collatz` | 13.924 | **13.870** | 14.027 | 51.889 | 752.472 |
| `matmul` | **45.274** | 45.619 | 45.510 | 82.862 | 3501.574 |
| `json_parse` | **8.904** | 9.111 | 12.321 | 38.044 | 38.062 |
| `nbody` | **26.999** | 46.477 | 44.281 | 96.569 | 3391.432 |

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
| _(floor: empty program)_ | _3.108_ | _98.675_ | _**101.783**_ | _66.324_ | _62.955_ | _67.484_ |
| `lcg` | 3.182 | 101.538 | **104.720** | 64.483 | 72.356 | 73.280 |
| `packet_classifier` | 3.304 | 101.915 | **105.219** | 65.500 | 73.857 | 73.572 |
| `ring_write` | 3.344 | 101.592 | **104.936** | 64.390 | 73.791 | 74.821 |
| `histogram_bins` | 3.429 | 121.122 | **124.551** | 64.077 | 76.555 | 78.535 |
| `prefix_scan` | 3.490 | 108.208 | **111.698** | 65.209 | 78.489 | 88.000 |
| `binary_search` | 3.629 | 111.876 | **115.505** | 65.195 | 75.330 | 80.816 |
| `sort_window` | 3.667 | 114.659 | **118.326** | 64.862 | 81.599 | 85.122 |
| `bloom_filter` | 3.936 | 111.528 | **115.464** | 65.910 | 82.281 | 84.658 |
| `hash_join` | 6.163 | 252.302 | **258.465** | 66.887 | 121.113 | 117.217 |
| `sieve` | 3.490 | 104.108 | **107.598** | 63.943 | 82.280 | 85.308 |
| `fib` | 3.240 | 98.760 | **102.000** | 63.889 | 71.738 | 72.733 |
| `collatz` | 3.411 | 102.620 | **106.031** | 64.238 | 73.333 | 75.937 |
| `matmul` | 3.740 | 107.801 | **111.541** | 64.899 | 84.934 | 97.666 |
| `json_parse` | 47.477 | 417.197 | **464.674** | 110.709 | 125.804 | 188.178 |
| `nbody` | 4.935 | 133.346 | **138.281** | 66.441 | 101.495 | 100.366 |

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
