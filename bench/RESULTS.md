# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T10:09:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `3ec9ff97f81b1bfdc65ed56f7cc4190537ffc4d8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31940782563 |
| NURL | `v0.43.0-19-g3ec9ff97` |
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
| _(floor: empty program)_ | _1.198_ | _1.241_ | _1.322_ | _15.526_ | _11.367_ |
| `lcg` | **30.155** | 32.766 | 30.579 | 1057.292 | 3127.667 |
| `packet_classifier` | 52.089 | **52.045** | 52.101 | 123.913 | 2562.527 |
| `ring_write` | 32.828 | 33.184 | **32.668** | 49.197 | 3723.367 |
| `histogram_bins` | **31.148** | 31.168 | 31.256 | 49.274 | 3591.268 |
| `prefix_scan` | **16.776** | 16.930 | 16.932 | 48.940 | 2789.095 |
| `binary_search` | **19.954** | 22.090 | 32.457 | 81.266 | 4746.077 |
| `sort_window` | **30.165** | 38.431 | 30.638 | 133.595 | 6702.472 |
| `bloom_filter` | 11.076 | **10.876** | 10.915 | 1863.936 | 5010.491 |
| `hash_join` | **18.112** | 19.781 | 19.994 | 2248.316 | 5165.431 |
| `sieve` | 33.162 | 32.781 | **32.606** | 70.348 | 2065.922 |
| `fib` | **17.408** | 20.475 | 19.565 | 81.903 | 665.288 |
| `collatz` | **11.288** | 11.586 | 12.177 | 44.035 | 420.836 |
| `matmul` | 15.396 | **15.005** | 15.238 | 52.619 | 1844.497 |
| `json_parse` | **5.727** | 6.231 | 7.295 | 23.690 | 24.528 |
| `nbody` | **16.345** | 23.703 | 21.789 | 62.035 | 1593.792 |

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
| _(floor: empty program)_ | _1.893_ | _52.631_ | _**54.524**_ | _35.511_ | _31.984_ | _46.707_ |
| `lcg` | 1.940 | 62.237 | **64.177** | 35.046 | 38.483 | 51.703 |
| `packet_classifier` | 2.298 | 55.294 | **57.592** | 34.515 | 38.264 | 49.157 |
| `ring_write` | 2.195 | 56.799 | **58.994** | 34.501 | 39.550 | 50.866 |
| `histogram_bins` | 2.319 | 69.772 | **72.091** | 35.759 | 39.237 | 52.789 |
| `prefix_scan` | 2.324 | 59.132 | **61.456** | 34.558 | 40.677 | 53.653 |
| `binary_search` | 2.529 | 62.073 | **64.602** | 36.508 | 44.946 | 55.304 |
| `sort_window` | 2.601 | 67.583 | **70.184** | 39.660 | 47.241 | 59.937 |
| `bloom_filter` | 2.535 | 60.912 | **63.447** | 35.987 | 44.627 | 54.669 |
| `hash_join` | 4.496 | 164.625 | **169.121** | 41.527 | 76.224 | 83.351 |
| `sieve` | 2.364 | 60.948 | **63.312** | 37.300 | 46.418 | 60.374 |
| `fib` | 2.201 | 54.356 | **56.557** | 34.769 | 37.246 | 50.310 |
| `collatz` | 2.243 | 60.984 | **63.227** | 36.886 | 37.727 | 52.139 |
| `matmul` | 2.451 | 60.898 | **63.349** | 35.503 | 46.943 | 69.584 |
| `json_parse` | 34.614 | 281.706 | **316.320** | 76.726 | 74.942 | 140.080 |
| `nbody` | 3.223 | 76.946 | **80.169** | 38.540 | 59.190 | 70.046 |

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
