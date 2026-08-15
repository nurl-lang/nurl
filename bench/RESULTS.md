# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-15T08:07:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3b5c4929d496f460b83c59ef5f1ebb10fa848bfe` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31873485408 |
| NURL | `v0.42.0-30-g3b5c4929` |
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
| _(floor: empty program)_ | _1.699_ | _1.739_ | _1.909_ | _23.807_ | _17.161_ |
| `lcg` | **39.129** | 39.394 | 39.319 | 2051.066 | 5145.846 |
| `packet_classifier` | 56.699 | **56.661** | 56.831 | 162.071 | 4470.769 |
| `ring_write` | **42.495** | 42.601 | 42.674 | 66.668 | 6309.119 |
| `histogram_bins` | **39.925** | 41.554 | 40.058 | 66.755 | 5945.783 |
| `prefix_scan` | 22.110 | **22.018** | 22.078 | 65.117 | 4548.485 |
| `binary_search` | **36.632** | 38.425 | 43.461 | 107.303 | 6126.331 |
| `sort_window` | **26.809** | 27.530 | 26.992 | 198.371 | 12641.828 |
| `bloom_filter` | **18.104** | 18.412 | 18.624 | 2863.707 | 7480.882 |
| `hash_join` | **27.159** | 30.384 | 30.088 | 3413.865 | 8287.193 |
| `sieve` | 21.051 | 20.957 | **20.686** | 67.457 | 3367.720 |
| `fib` | **25.545** | 30.096 | 28.356 | 132.975 | 1341.694 |
| `collatz` | 12.498 | **12.468** | 12.534 | 50.935 | 716.742 |
| `matmul` | 33.777 | **33.627** | 34.129 | 76.989 | 3250.078 |
| `json_parse` | 9.161 | **8.883** | 11.866 | 35.318 | 38.531 |
| `nbody` | **25.624** | 41.103 | 39.352 | 101.779 | 3099.352 |

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
| _(floor: empty program)_ | _2.832_ | _91.475_ | _**94.307**_ | _59.039_ | _57.892_ | _61.365_ |
| `lcg` | 2.917 | 92.427 | **95.344** | 58.869 | 68.505 | 70.014 |
| `packet_classifier` | 2.993 | 93.743 | **96.736** | 59.628 | 68.188 | 68.865 |
| `ring_write` | 3.155 | 95.525 | **98.680** | 60.024 | 68.464 | 70.733 |
| `histogram_bins` | 3.226 | 115.883 | **119.109** | 59.774 | 73.109 | 72.588 |
| `prefix_scan` | 3.196 | 100.102 | **103.298** | 59.906 | 74.987 | 71.932 |
| `binary_search` | 3.302 | 103.289 | **106.591** | 58.656 | 69.521 | 74.062 |
| `sort_window` | 3.437 | 107.461 | **110.898** | 59.840 | 77.891 | 80.307 |
| `bloom_filter` | 3.668 | 105.503 | **109.171** | 61.686 | 77.503 | 96.956 |
| `hash_join` | 5.993 | 259.497 | **265.490** | 63.755 | 123.263 | 111.288 |
| `sieve` | 3.242 | 100.401 | **103.643** | 59.917 | 79.869 | 80.276 |
| `fib` | 3.016 | 93.502 | **96.518** | 59.908 | 67.679 | 68.272 |
| `collatz` | 3.171 | 97.282 | **100.453** | 60.317 | 69.396 | 69.824 |
| `matmul` | 3.503 | 102.528 | **106.031** | 60.162 | 81.871 | 90.744 |
| `json_parse` | 48.849 | 436.707 | **485.556** | 107.678 | 127.755 | 181.106 |
| `nbody` | 4.750 | 127.962 | **132.712** | 61.492 | 99.830 | 92.377 |

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
