# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-12T03:37:03Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0ced45e72e1b1c18c2fe3f3a9554dd54af9c0667` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31560378423 |
| NURL | `v0.39.0` |
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
| _(floor: empty program)_ | _1.802_ | _1.851_ | _2.038_ | _26.755_ | _19.050_ |
| `lcg` | **44.295** | 44.502 | 44.528 | 1836.024 | 5302.508 |
| `packet_classifier` | **63.691** | 63.779 | 63.895 | 158.784 | 4865.745 |
| `ring_write` | **47.853** | 48.023 | 48.142 | 75.555 | 6596.123 |
| `histogram_bins` | **44.918** | **44.918** | 44.978 | 74.803 | 6922.183 |
| `prefix_scan` | 25.613 | **24.920** | 25.079 | 71.904 | 4813.153 |
| `binary_search` | **35.452** | 35.828 | 46.084 | 111.660 | 6454.356 |
| `sort_window` | 30.837 | 30.962 | **30.407** | 168.298 | 11611.301 |
| `bloom_filter` | **19.955** | 20.575 | 20.865 | 2771.456 | 7995.242 |
| `hash_join` | **29.284** | 30.787 | 31.345 | 3416.128 | 8273.952 |
| `sieve` | 20.576 | **20.423** | 20.432 | 70.542 | 3446.297 |
| `fib` | **28.096** | 33.440 | 29.622 | 143.939 | 1287.539 |
| `collatz` | **14.025** | 14.061 | 14.074 | 54.324 | 751.529 |
| `matmul` | **47.084** | 47.414 | 47.596 | 85.487 | 3535.146 |
| `json_parse` | **8.773** | 9.221 | 12.511 | 40.412 | 39.795 |
| `nbody` | 46.462 | 46.402 | **44.297** | 96.861 | 3318.470 |

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
| _(floor: empty program)_ | _3.053_ | _94.400_ | _**97.453**_ | _67.711_ | _66.510_ |
| `lcg` | 3.261 | 99.317 | **102.578** | 75.915 | 77.347 |
| `packet_classifier` | 3.237 | 99.926 | **103.163** | 76.614 | 75.268 |
| `ring_write` | 3.404 | 99.733 | **103.137** | 77.024 | 77.375 |
| `histogram_bins` | 3.482 | 103.040 | **106.522** | 79.128 | 80.294 |
| `prefix_scan` | 3.916 | 116.414 | **120.330** | 89.226 | 78.727 |
| `binary_search` | 3.593 | 103.341 | **106.934** | 77.965 | 82.025 |
| `sort_window` | 3.651 | 111.200 | **114.851** | 83.736 | 86.498 |
| `bloom_filter` | 3.852 | 107.205 | **111.057** | 84.872 | 83.065 |
| `hash_join` | 6.058 | 210.342 | **216.400** | 122.859 | 118.002 |
| `sieve` | 3.460 | 103.607 | **107.067** | 83.792 | 86.662 |
| `fib` | 3.216 | 96.152 | **99.368** | 74.442 | 73.397 |
| `collatz` | 3.412 | 102.345 | **105.757** | 77.709 | 78.059 |
| `matmul` | 3.821 | 112.836 | **116.657** | 91.945 | 105.906 |
| `json_parse` | 43.717 | 525.941 | **569.658** | 130.131 | 194.948 |
| `nbody` | 4.899 | 120.375 | **125.274** | 105.219 | 102.892 |

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
