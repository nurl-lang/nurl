# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T08:07:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `49d54ca4237bb47b33c717542681930b56fcc970` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30614904352 |
| NURL | `v0.29.0-80-g49d54ca` |
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
| _(floor: empty program)_ | _1.661_ | _1.715_ | _1.874_ | _24.148_ | _18.483_ |
| `lcg` | 39.398 | **39.265** | 39.414 | 1881.864 | 5160.414 |
| `packet_classifier` | **56.651** | 56.822 | 56.898 | 163.631 | 4348.605 |
| `ring_write` | **42.356** | 42.368 | 42.539 | 67.651 | 6341.360 |
| `histogram_bins` | **39.794** | 41.607 | 40.015 | 68.241 | 6174.902 |
| `prefix_scan` | **21.868** | 21.997 | 21.981 | 66.534 | 4588.259 |
| `binary_search` | 40.024 | **38.785** | 43.481 | 107.716 | 6092.172 |
| `sort_window` | 27.714 | 27.791 | **26.876** | 198.606 | 11406.727 |
| `bloom_filter` | **18.094** | 18.344 | 18.497 | 2814.930 | 8097.531 |
| `hash_join` | **28.265** | 30.222 | 30.021 | 3424.568 | 8435.451 |
| `sieve` | 20.462 | 20.442 | **18.831** | 67.841 | 3340.414 |
| `fib` | **25.459** | 30.255 | 28.321 | 133.174 | 1354.508 |
| `collatz` | **12.472** | 12.476 | 12.588 | 48.971 | 712.775 |
| `matmul` | 33.514 | **33.420** | 33.633 | 79.305 | 3150.778 |
| `json_parse` | **8.475** | 8.937 | 11.796 | 36.697 | 37.437 |
| `nbody` | 40.866 | 41.079 | **39.065** | 102.648 | 3050.876 |

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
| _(floor: empty program)_ | _3.325_ | _78.512_ | _**81.837**_ | _56.926_ | _60.895_ |
| `lcg` | 3.208 | 82.972 | **86.180** | 65.509 | 69.549 |
| `packet_classifier` | 3.396 | 85.998 | **89.394** | 68.074 | 68.697 |
| `ring_write` | 3.530 | 89.709 | **93.239** | 69.313 | 71.839 |
| `histogram_bins` | 3.777 | 91.102 | **94.879** | 72.772 | 75.748 |
| `prefix_scan` | 3.769 | 94.782 | **98.551** | 74.048 | 74.745 |
| `binary_search` | 4.001 | 93.570 | **97.571** | 72.718 | 77.151 |
| `sort_window` | 4.247 | 100.006 | **104.253** | 75.675 | 80.208 |
| `bloom_filter` | 4.377 | 97.787 | **102.164** | 77.414 | 76.871 |
| `hash_join` | 8.895 | 209.834 | **218.729** | 119.372 | 111.073 |
| `sieve` | 3.847 | 96.361 | **100.208** | 81.792 | 83.476 |
| `fib` | 3.223 | 84.680 | **87.903** | 67.615 | 68.730 |
| `collatz` | 3.581 | 87.509 | **91.090** | 67.290 | 70.289 |
| `matmul` | 4.445 | 97.005 | **101.450** | 80.646 | 91.699 |
| `json_parse` | 74.172 | 726.292 | **800.464** | 126.255 | 183.398 |
| `nbody` | 6.817 | 107.648 | **114.465** | 97.747 | 95.653 |

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
