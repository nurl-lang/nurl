# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T14:17:14Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `64b3dd335a37b8435c6660fed114836f14131337` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31261380882 |
| NURL | `v0.35.1-35-g64b3dd33` |
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
| _(floor: empty program)_ | _1.700_ | _1.777_ | _1.913_ | _24.475_ | _18.345_ |
| `lcg` | **39.376** | 39.517 | 39.629 | 1896.124 | 5131.392 |
| `packet_classifier` | **56.493** | 56.596 | 56.781 | 162.848 | 4339.701 |
| `ring_write` | **42.426** | 42.535 | 42.592 | 66.265 | 6387.868 |
| `histogram_bins` | **39.782** | 41.477 | 40.026 | 66.615 | 5936.915 |
| `prefix_scan` | **21.888** | 21.987 | 22.180 | 65.450 | 4422.754 |
| `binary_search` | 40.122 | **38.522** | 43.641 | 108.549 | 5993.617 |
| `sort_window` | 27.382 | 27.523 | **26.876** | 197.128 | 11502.326 |
| `bloom_filter` | **18.082** | 18.324 | 18.635 | 2863.858 | 7545.331 |
| `hash_join` | **28.008** | 30.347 | 30.086 | 3432.715 | 8421.203 |
| `sieve` | 21.037 | 20.768 | **20.487** | 67.341 | 3203.810 |
| `fib` | **25.694** | 30.197 | 28.388 | 131.712 | 1342.072 |
| `collatz` | **12.543** | 12.605 | 12.617 | 49.970 | 709.956 |
| `matmul` | **33.609** | 33.679 | 34.000 | 77.664 | 3355.706 |
| `json_parse` | 42.444 | **8.949** | 11.737 | 36.540 | 38.508 |
| `nbody` | 41.148 | 41.289 | **39.337** | 104.489 | 3115.134 |

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
| _(floor: empty program)_ | _3.415_ | _83.163_ | _**86.578**_ | _62.874_ | _63.419_ |
| `lcg` | 2.897 | 91.465 | **94.362** | 72.040 | 72.084 |
| `packet_classifier` | 2.902 | 89.512 | **92.414** | 68.898 | 68.476 |
| `ring_write` | 2.915 | 87.590 | **90.505** | 67.218 | 70.659 |
| `histogram_bins` | 2.991 | 93.825 | **96.816** | 72.190 | 73.795 |
| `prefix_scan` | 3.010 | 92.808 | **95.818** | 72.556 | 71.347 |
| `binary_search` | 3.140 | 93.143 | **96.283** | 69.505 | 74.211 |
| `sort_window` | 3.202 | 99.806 | **103.008** | 75.629 | 79.543 |
| `bloom_filter` | 3.406 | 99.943 | **103.349** | 77.784 | 76.660 |
| `hash_join` | 5.461 | 210.748 | **216.209** | 119.332 | 110.682 |
| `sieve` | 3.049 | 96.015 | **99.064** | 84.346 | 80.105 |
| `fib` | 2.861 | 90.121 | **92.982** | 70.265 | 70.970 |
| `collatz` | 3.021 | 94.002 | **97.023** | 71.618 | 71.981 |
| `matmul` | 3.249 | 99.205 | **102.454** | 81.760 | 93.843 |
| `json_parse` | 41.596 | 541.435 | **583.031** | 124.178 | 182.171 |
| `nbody` | 4.373 | 112.897 | **117.270** | 99.860 | 92.957 |

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
