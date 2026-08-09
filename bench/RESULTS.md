# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-09T13:53:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `12bca1cdbfc5a92f00bf70a4738a2366c70ad2d0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31316790863 |
| NURL | `v0.36.0-10-g12bca1cd` |
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
| _(floor: empty program)_ | _1.431_ | _1.463_ | _1.548_ | _21.891_ | _15.756_ |
| `lcg` | **40.687** | 40.859 | 40.895 | 1513.145 | 4480.121 |
| `packet_classifier` | **65.180** | 71.447 | 69.119 | 170.574 | 3666.122 |
| `ring_write` | 44.966 | **44.698** | 45.160 | 65.807 | 5238.533 |
| `histogram_bins` | 41.838 | **41.717** | 41.734 | 69.392 | 5105.607 |
| `prefix_scan` | **22.667** | 22.846 | 22.896 | 65.915 | 3881.020 |
| `binary_search` | 34.467 | **32.138** | 46.022 | 113.141 | 6420.337 |
| `sort_window` | 41.667 | 52.231 | **40.920** | 182.050 | 10430.312 |
| `bloom_filter` | **14.420** | 14.617 | 14.719 | 2413.303 | 6487.429 |
| `hash_join` | **24.946** | 26.835 | 27.470 | 3046.422 | 7173.725 |
| `sieve` | **35.971** | 36.305 | 36.431 | 83.500 | 2599.655 |
| `fib` | 30.106 | 31.344 | **26.171** | 114.140 | 903.530 |
| `collatz` | **15.328** | 15.461 | 16.154 | 60.342 | 568.972 |
| `matmul` | 20.749 | 20.733 | **20.637** | 73.921 | 2562.988 |
| `json_parse` | 35.757 | **7.831** | 9.763 | 33.130 | 33.646 |
| `nbody` | 32.928 | 32.891 | **30.233** | 81.417 | 2146.801 |

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
| _(floor: empty program)_ | _2.369_ | _68.556_ | _**70.925**_ | _46.892_ | _57.799_ |
| `lcg` | 2.528 | 74.192 | **76.720** | 56.372 | 64.115 |
| `packet_classifier` | 2.618 | 75.134 | **77.752** | 57.897 | 65.522 |
| `ring_write` | 2.695 | 76.049 | **78.744** | 58.583 | 66.478 |
| `histogram_bins` | 2.777 | 80.893 | **83.670** | 59.672 | 67.922 |
| `prefix_scan` | 2.782 | 78.593 | **81.375** | 60.135 | 67.493 |
| `binary_search` | 2.913 | 78.204 | **81.117** | 58.183 | 71.711 |
| `sort_window` | 2.919 | 84.065 | **86.984** | 62.797 | 75.472 |
| `bloom_filter` | 3.158 | 85.378 | **88.536** | 66.021 | 72.134 |
| `hash_join` | 5.258 | 184.670 | **189.928** | 106.760 | 109.711 |
| `sieve` | 2.804 | 81.745 | **84.549** | 66.786 | 77.619 |
| `fib` | 2.591 | 74.571 | **77.162** | 55.549 | 62.809 |
| `collatz` | 2.733 | 76.888 | **79.621** | 58.580 | 66.912 |
| `matmul` | 3.051 | 85.151 | **88.202** | 70.362 | 90.881 |
| `json_parse` | 41.098 | 472.780 | **513.878** | 107.348 | 181.661 |
| `nbody` | 3.944 | 94.997 | **98.941** | 84.216 | 89.657 |

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
