# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T20:18:32Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `14cc967e1a8371a8e1a74465447e7ece709f7aa2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30946902135 |
| NURL | `v0.32.0-51-g14cc967e` |
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
| _(floor: empty program)_ | _1.822_ | _1.827_ | _1.996_ | _25.247_ | _18.222_ |
| `lcg` | **44.427** | 44.554 | 44.692 | 1833.875 | 5415.097 |
| `packet_classifier` | **63.811** | 63.854 | 64.040 | 158.618 | 4676.850 |
| `ring_write` | **48.051** | 48.124 | 48.124 | 74.134 | 6573.180 |
| `histogram_bins` | 45.073 | **45.039** | 45.112 | 76.085 | 6277.766 |
| `prefix_scan` | **24.746** | 24.986 | 25.168 | 72.780 | 4722.811 |
| `binary_search` | **35.837** | 36.147 | 46.177 | 112.847 | 6499.962 |
| `sort_window` | 31.179 | 31.171 | **30.493** | 165.805 | 11120.075 |
| `bloom_filter` | **20.265** | 20.872 | 21.080 | 2760.435 | 8252.012 |
| `hash_join` | **29.641** | 31.130 | 31.468 | 3427.695 | 8275.440 |
| `sieve` | 21.057 | **20.663** | 20.882 | 72.867 | 4016.060 |
| `fib` | **28.195** | 33.652 | 29.586 | 142.525 | 1281.264 |
| `collatz` | **13.929** | 14.016 | 14.111 | 54.692 | 757.893 |
| `matmul` | **45.479** | 46.987 | 46.235 | 84.031 | 3565.040 |
| `json_parse` | **8.684** | 9.187 | 12.653 | 38.878 | 39.868 |
| `nbody` | 46.279 | 46.564 | **44.242** | 95.995 | 3296.119 |

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
| _(floor: empty program)_ | _3.092_ | _94.982_ | _**98.074**_ | _68.155_ | _66.166_ |
| `lcg` | 3.035 | 98.738 | **101.773** | 77.787 | 73.553 |
| `packet_classifier` | 3.207 | 101.610 | **104.817** | 78.718 | 76.660 |
| `ring_write` | 3.344 | 103.773 | **107.117** | 76.807 | 76.270 |
| `histogram_bins` | 3.341 | 104.643 | **107.984** | 81.185 | 81.455 |
| `prefix_scan` | 3.393 | 107.044 | **110.437** | 80.927 | 80.381 |
| `binary_search` | 3.549 | 107.445 | **110.994** | 80.815 | 84.812 |
| `sort_window` | 3.537 | 114.710 | **118.247** | 84.254 | 86.806 |
| `bloom_filter` | 3.731 | 110.817 | **114.548** | 86.218 | 82.833 |
| `hash_join` | 5.986 | 216.571 | **222.557** | 127.453 | 121.775 |
| `sieve` | 3.341 | 106.392 | **109.733** | 87.332 | 86.971 |
| `fib` | 3.235 | 101.114 | **104.349** | 75.961 | 73.326 |
| `collatz` | 3.315 | 103.254 | **106.569** | 76.525 | 77.079 |
| `matmul` | 3.553 | 109.927 | **113.480** | 89.784 | 101.976 |
| `json_parse` | 39.410 | 507.795 | **547.205** | 132.070 | 196.232 |
| `nbody` | 4.663 | 121.362 | **126.025** | 104.038 | 101.321 |

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
