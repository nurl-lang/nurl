# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T13:07:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `5eb29c7077e5d2d8dc936f7b0ea654cb072f151c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31948767764 |
| NURL | `v0.44.0-2-g5eb29c70` |
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
| _(floor: empty program)_ | _1.270_ | _1.315_ | _1.423_ | _16.488_ | _11.269_ |
| `lcg` | 28.358 | **28.053** | 33.094 | 1057.839 | 2856.171 |
| `packet_classifier` | **40.582** | 40.621 | 40.711 | 124.451 | 2593.198 |
| `ring_write` | 28.262 | **28.077** | 28.201 | 47.371 | 3500.555 |
| `histogram_bins` | 28.182 | **28.112** | 28.200 | 47.299 | 3296.432 |
| `prefix_scan` | **15.620** | 15.621 | 15.723 | 45.937 | 2409.468 |
| `binary_search` | 14.233 | **14.204** | 15.324 | 65.803 | 3458.269 |
| `sort_window` | **19.670** | 23.538 | 19.791 | 129.068 | 6854.727 |
| `bloom_filter` | **8.660** | 8.670 | 8.744 | 1558.423 | 4180.280 |
| `hash_join` | **15.663** | 17.774 | 18.215 | 1843.467 | 4378.202 |
| `sieve` | 11.804 | 11.871 | **11.598** | 43.818 | 1822.831 |
| `fib` | 18.726 | **18.679** | 19.398 | 73.496 | 663.525 |
| `collatz` | 9.119 | **9.072** | 9.156 | 33.707 | 441.891 |
| `matmul` | **19.937** | 19.940 | 20.072 | 51.545 | 1786.430 |
| `json_parse` | **4.964** | 5.096 | 6.913 | 22.895 | 22.350 |
| `nbody` | **16.184** | 24.410 | 22.965 | 56.473 | 1409.504 |

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
| _(floor: empty program)_ | _2.368_ | _67.083_ | _**69.451**_ | _44.232_ | _44.107_ | _50.029_ |
| `lcg` | 2.348 | 70.622 | **72.970** | 44.963 | 49.746 | 55.174 |
| `packet_classifier` | 2.403 | 69.959 | **72.362** | 43.538 | 51.376 | 78.731 |
| `ring_write` | 2.381 | 69.880 | **72.261** | 43.737 | 50.821 | 54.972 |
| `histogram_bins` | 2.493 | 82.571 | **85.064** | 44.032 | 53.998 | 57.014 |
| `prefix_scan` | 2.477 | 72.196 | **74.673** | 43.460 | 52.713 | 56.812 |
| `binary_search` | 2.564 | 75.422 | **77.986** | 43.818 | 51.873 | 58.360 |
| `sort_window` | 2.576 | 77.568 | **80.144** | 43.865 | 56.801 | 62.615 |
| `bloom_filter` | 2.713 | 74.783 | **77.496** | 43.557 | 57.053 | 58.620 |
| `hash_join` | 4.074 | 157.444 | **161.518** | 44.284 | 83.302 | 81.986 |
| `sieve` | 2.517 | 73.407 | **75.924** | 44.098 | 57.117 | 62.712 |
| `fib` | 2.353 | 68.814 | **71.167** | 43.444 | 50.669 | 54.187 |
| `collatz` | 2.445 | 70.103 | **72.548** | 43.995 | 51.206 | 56.988 |
| `matmul` | 2.587 | 74.162 | **76.749** | 43.501 | 57.334 | 70.392 |
| `json_parse` | 28.484 | 254.796 | **283.280** | 70.551 | 82.317 | 131.108 |
| `nbody` | 3.322 | 88.561 | **91.883** | 44.704 | 65.948 | 70.366 |

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
