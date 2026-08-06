# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-06T12:39:20Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1021-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `c75161be3d584c9ea3459e23053541c87de3af0c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31101995643 |
| NURL | `v0.33.0-74-gc75161be` |
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
| _(floor: empty program)_ | _1.677_ | _1.739_ | _1.886_ | _21.462_ | _16.853_ |
| `lcg` | **39.365** | 39.531 | 39.611 | 2071.195 | 5179.771 |
| `packet_classifier` | 56.512 | **56.504** | 56.657 | 162.842 | 4439.358 |
| `ring_write` | **42.555** | 42.653 | 42.639 | 65.471 | 6293.811 |
| `histogram_bins` | **40.080** | 41.717 | 40.135 | 68.292 | 6159.043 |
| `prefix_scan` | 22.068 | **22.000** | 22.114 | 67.393 | 4493.334 |
| `binary_search` | 40.055 | **38.664** | 43.583 | 107.310 | 6205.795 |
| `sort_window` | 27.510 | 27.664 | **27.117** | 199.169 | 11285.330 |
| `bloom_filter` | **18.180** | 18.410 | 18.780 | 2853.566 | 7271.150 |
| `hash_join` | **28.257** | 30.485 | 30.300 | 3405.092 | 8219.994 |
| `sieve` | **20.685** | 20.865 | 21.276 | 68.672 | 3186.535 |
| `fib` | **25.646** | 30.313 | 28.546 | 132.619 | 1345.012 |
| `collatz` | **12.597** | 12.680 | 12.717 | 50.472 | 715.455 |
| `matmul` | 33.877 | **33.833** | 33.856 | 77.836 | 4082.073 |
| `json_parse` | **8.801** | 8.886 | 11.855 | 35.716 | 37.578 |
| `nbody` | 40.909 | 41.120 | **39.198** | 101.586 | 3062.050 |

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
| _(floor: empty program)_ | _2.799_ | _83.615_ | _**86.414**_ | _59.337_ | _61.906_ |
| `lcg` | 2.758 | 86.349 | **89.107** | 67.328 | 68.438 |
| `packet_classifier` | 2.791 | 90.124 | **92.915** | 72.014 | 72.482 |
| `ring_write` | 2.917 | 90.031 | **92.948** | 71.380 | 69.961 |
| `histogram_bins` | 3.090 | 99.317 | **102.407** | 73.767 | 73.574 |
| `prefix_scan` | 3.016 | 96.407 | **99.423** | 74.787 | 72.257 |
| `binary_search` | 3.118 | 97.443 | **100.561** | 72.831 | 75.800 |
| `sort_window` | 3.169 | 99.645 | **102.814** | 77.343 | 79.689 |
| `bloom_filter` | 3.350 | 98.920 | **102.270** | 77.493 | 75.274 |
| `hash_join` | 5.386 | 211.437 | **216.823** | 121.760 | 111.615 |
| `sieve` | 3.077 | 98.367 | **101.444** | 79.382 | 83.397 |
| `fib` | 2.789 | 91.453 | **94.242** | 70.165 | 68.546 |
| `collatz` | 2.940 | 95.201 | **98.141** | 71.137 | 71.527 |
| `matmul` | 3.255 | 101.640 | **104.895** | 84.924 | 95.517 |
| `json_parse` | 40.815 | 523.280 | **564.095** | 129.543 | 181.484 |
| `nbody` | 4.246 | 110.827 | **115.073** | 100.070 | 94.104 |

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
