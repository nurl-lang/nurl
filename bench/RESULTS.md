# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T17:44:25Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `bc2ca9053f08fa4a033853686fa6f515d6de2ceb` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30566901185 |
| NURL | `v0.29.0-49-gbc2ca90` |
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
| _(floor: empty program)_ | _1.689_ | _1.782_ | _1.891_ | _22.556_ | _17.503_ |
| `lcg` | **39.486** | 39.541 | 39.697 | 1882.159 | 5132.766 |
| `packet_classifier` | **56.621** | 56.652 | 56.829 | 163.870 | 4490.862 |
| `ring_write` | 42.619 | **42.593** | 42.926 | 67.310 | 6516.735 |
| `histogram_bins` | **39.964** | 41.836 | 40.349 | 67.688 | 6003.171 |
| `prefix_scan` | **22.160** | 22.337 | 22.465 | 67.727 | 4602.167 |
| `binary_search` | 40.271 | **38.984** | 43.597 | 107.416 | 5964.414 |
| `sort_window` | 27.766 | 27.832 | **27.367** | 198.319 | 11356.582 |
| `bloom_filter` | **18.394** | 18.593 | 18.855 | 2876.283 | 7499.453 |
| `hash_join` | **28.661** | 30.703 | 30.316 | 3413.157 | 8305.928 |
| `sieve` | 21.018 | **20.608** | 20.614 | 69.200 | 3203.768 |
| `fib` | **25.705** | 30.473 | 28.682 | 132.460 | 1357.919 |
| `collatz` | **12.476** | 12.502 | 12.645 | 50.952 | 712.543 |
| `matmul` | **33.890** | 33.922 | 34.157 | 78.877 | 3192.195 |
| `json_parse` | **8.578** | 9.003 | 11.800 | 36.492 | 38.463 |
| `nbody` | 40.921 | 41.055 | **39.211** | 100.277 | 3139.524 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns. The floor row is what each
toolchain costs for a program that does nothing — for NURL that is
dominated by the LTO link every NURL binary pays for, so subtract it to
read the marginal cost of the benchmark itself. Node and Python have no
column here: they compile at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.080_ | _83.652_ | _**86.732**_ | _57.878_ | _63.997_ |
| `lcg` | 3.205 | 84.394 | **87.599** | 70.857 | 72.924 |
| `packet_classifier` | 3.313 | 86.619 | **89.932** | 70.322 | 73.177 |
| `ring_write` | 3.534 | 89.992 | **93.526** | 72.124 | 76.303 |
| `histogram_bins` | 3.667 | 94.898 | **98.565** | 71.682 | 75.131 |
| `prefix_scan` | 3.761 | 97.350 | **101.111** | 77.092 | 77.485 |
| `binary_search` | 4.038 | 95.529 | **99.567** | 73.306 | 78.965 |
| `sort_window` | 4.145 | 104.380 | **108.525** | 79.545 | 83.907 |
| `bloom_filter` | 4.460 | 101.314 | **105.774** | 81.735 | 77.673 |
| `hash_join` | 8.757 | 211.490 | **220.247** | 120.343 | 111.687 |
| `sieve` | 3.834 | 97.863 | **101.697** | 81.950 | 82.876 |
| `fib` | 3.248 | 87.114 | **90.362** | 71.084 | 70.278 |
| `collatz` | 3.568 | 95.775 | **99.343** | 71.532 | 72.499 |
| `matmul` | 4.636 | 102.360 | **106.996** | 86.557 | 95.518 |
| `json_parse` | 75.276 | 738.301 | **813.577** | 129.064 | 184.744 |
| `nbody` | 6.924 | 112.863 | **119.787** | 98.544 | 94.898 |

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
