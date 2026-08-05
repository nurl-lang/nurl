# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T17:38:26Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e4c00acfd8af97fa0eedd929a27cfd61e4408b45` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31030583438 |
| NURL | `v0.33.0-22-ge4c00acf` |
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
| _(floor: empty program)_ | _1.656_ | _1.734_ | _1.881_ | _24.008_ | _17.457_ |
| `lcg` | **39.387** | 39.494 | 39.412 | 1874.334 | 5104.851 |
| `packet_classifier` | **56.613** | 56.632 | 56.887 | 162.613 | 4540.826 |
| `ring_write` | 42.625 | **42.601** | 42.789 | 68.257 | 6209.599 |
| `histogram_bins` | **39.662** | 41.402 | 39.946 | 68.626 | 6173.791 |
| `prefix_scan` | **21.901** | 21.924 | 22.060 | 64.315 | 4438.880 |
| `binary_search` | 39.872 | **38.505** | 43.222 | 105.527 | 6501.145 |
| `sort_window` | 27.409 | 27.511 | **27.070** | 198.382 | 11620.390 |
| `bloom_filter` | **18.130** | 18.419 | 18.762 | 2843.842 | 7584.805 |
| `hash_join` | **28.226** | 30.349 | 29.947 | 3449.104 | 8077.497 |
| `sieve` | 19.212 | 18.618 | **18.091** | 66.540 | 3275.553 |
| `fib` | **25.652** | 30.477 | 28.389 | 131.677 | 1360.606 |
| `collatz` | **12.512** | 12.525 | 12.672 | 53.178 | 710.020 |
| `matmul` | 33.577 | **33.509** | 33.713 | 75.929 | 3190.984 |
| `json_parse` | **8.732** | 8.818 | 11.817 | 36.471 | 37.878 |
| `nbody` | 41.027 | 41.158 | **39.468** | 102.212 | 3033.631 |

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
| _(floor: empty program)_ | _2.929_ | _87.749_ | _**90.678**_ | _62.223_ | _67.581_ |
| `lcg` | 2.753 | 90.814 | **93.567** | 69.578 | 70.925 |
| `packet_classifier` | 2.820 | 90.326 | **93.146** | 68.873 | 69.347 |
| `ring_write` | 2.872 | 91.544 | **94.416** | 70.937 | 71.652 |
| `histogram_bins` | 2.955 | 94.749 | **97.704** | 72.295 | 72.701 |
| `prefix_scan` | 3.021 | 95.412 | **98.433** | 72.497 | 72.668 |
| `binary_search` | 3.103 | 91.513 | **94.616** | 69.699 | 74.352 |
| `sort_window` | 3.152 | 99.501 | **102.653** | 76.656 | 80.990 |
| `bloom_filter` | 3.323 | 97.054 | **100.377** | 78.843 | 74.980 |
| `hash_join` | 5.397 | 211.916 | **217.313** | 120.719 | 113.338 |
| `sieve` | 2.974 | 94.362 | **97.336** | 80.761 | 80.648 |
| `fib` | 2.804 | 90.604 | **93.408** | 70.290 | 70.491 |
| `collatz` | 2.947 | 93.670 | **96.617** | 70.831 | 72.166 |
| `matmul` | 3.261 | 98.828 | **102.089** | 82.048 | 96.952 |
| `json_parse` | 40.242 | 517.191 | **557.433** | 127.273 | 182.109 |
| `nbody` | 4.316 | 114.149 | **118.465** | 99.784 | 94.481 |

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
