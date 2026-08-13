# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T18:28:26Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `6998db78d958231a0dca8e40d789945b0cb18e67` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31730507346 |
| NURL | `v0.40.0-4-g6998db78` |
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
| _(floor: empty program)_ | _1.640_ | _1.716_ | _1.853_ | _23.346_ | _17.030_ |
| `lcg` | **39.312** | 39.342 | 39.398 | 1878.382 | 5282.925 |
| `packet_classifier` | **56.407** | 56.466 | 56.529 | 161.689 | 4456.060 |
| `ring_write` | **42.363** | **42.363** | 42.487 | 65.519 | 7091.568 |
| `histogram_bins` | **39.630** | 41.382 | 39.833 | 65.108 | 6152.329 |
| `prefix_scan` | **21.857** | 21.905 | 22.020 | 64.542 | 4702.956 |
| `binary_search` | **36.334** | 38.366 | 43.262 | 105.502 | 6943.119 |
| `sort_window` | **26.656** | 27.468 | 26.835 | 197.378 | 11291.461 |
| `bloom_filter` | **17.932** | 18.234 | 18.464 | 2834.820 | 7607.796 |
| `hash_join` | **27.149** | 30.169 | 29.972 | 3482.231 | 8179.568 |
| `sieve` | 18.566 | **17.900** | 18.182 | 66.256 | 3248.919 |
| `fib` | **25.175** | 29.900 | 28.182 | 130.161 | 1343.928 |
| `collatz` | 12.485 | **12.451** | 12.492 | 47.465 | 709.667 |
| `matmul` | **33.465** | 33.536 | 33.825 | 75.813 | 3312.584 |
| `json_parse` | 8.940 | **8.838** | 11.739 | 35.492 | 37.346 |
| `nbody` | **25.341** | 40.855 | 39.057 | 99.966 | 3135.296 |

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
| _(floor: empty program)_ | _2.702_ | _90.303_ | _**93.005**_ | _58.190_ | _57.939_ | _60.738_ |
| `lcg` | 2.863 | 93.179 | **96.042** | 59.208 | 65.050 | 67.319 |
| `packet_classifier` | 2.895 | 91.236 | **94.131** | 57.350 | 66.599 | 68.363 |
| `ring_write` | 3.006 | 92.324 | **95.330** | 57.595 | 67.679 | 68.592 |
| `histogram_bins` | 3.086 | 112.617 | **115.703** | 57.888 | 72.736 | 71.018 |
| `prefix_scan` | 3.096 | 98.730 | **101.826** | 58.270 | 71.861 | 70.693 |
| `binary_search` | 3.308 | 101.922 | **105.230** | 58.461 | 68.907 | 73.375 |
| `sort_window` | 3.319 | 106.505 | **109.824** | 59.759 | 75.012 | 77.299 |
| `bloom_filter` | 3.554 | 101.231 | **104.785** | 58.613 | 75.325 | 74.180 |
| `hash_join` | 5.873 | 253.420 | **259.293** | 61.079 | 118.879 | 109.250 |
| `sieve` | 3.112 | 95.976 | **99.088** | 58.150 | 78.084 | 78.323 |
| `fib` | 2.878 | 90.100 | **92.978** | 57.567 | 66.029 | 65.774 |
| `collatz` | 3.053 | 93.706 | **96.759** | 57.854 | 67.478 | 68.619 |
| `matmul` | 3.387 | 99.137 | **102.524** | 58.229 | 79.017 | 91.732 |
| `json_parse` | 46.751 | 425.613 | **472.364** | 103.186 | 121.350 | 176.511 |
| `nbody` | 4.552 | 123.879 | **128.431** | 60.009 | 95.596 | 90.722 |

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
