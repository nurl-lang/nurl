# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T07:14:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377692 KiB |
| Commit | `379e6138b3eda7dd69e2daa9f43ad24dbee08088` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31467875696 |
| NURL | `v0.37.1` |
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
| _(floor: empty program)_ | _1.659_ | _1.701_ | _1.829_ | _22.088_ | _16.680_ |
| `lcg` | **39.197** | 39.287 | 39.308 | 1875.125 | 5382.517 |
| `packet_classifier` | **56.366** | 56.376 | 56.530 | 161.903 | 4410.482 |
| `ring_write` | 42.355 | **42.311** | 42.453 | 65.730 | 6121.362 |
| `histogram_bins` | **39.664** | 41.342 | 39.831 | 66.437 | 6287.420 |
| `prefix_scan` | **21.873** | 21.917 | 22.020 | 64.787 | 4604.486 |
| `binary_search` | 39.985 | **38.466** | 43.366 | 105.447 | 6467.078 |
| `sort_window` | 27.350 | 27.392 | **26.928** | 198.005 | 11383.535 |
| `bloom_filter` | **17.994** | 18.221 | 18.446 | 2832.921 | 7671.526 |
| `hash_join` | **28.041** | 30.146 | 30.113 | 3423.529 | 8140.734 |
| `sieve` | 20.265 | **20.074** | 20.248 | 67.462 | 3276.207 |
| `fib` | **25.246** | 30.101 | 28.265 | 130.343 | 1363.515 |
| `collatz` | 12.436 | **12.396** | 12.506 | 47.490 | 707.989 |
| `matmul` | 33.450 | **33.434** | 33.794 | 76.942 | 3079.075 |
| `json_parse` | **8.835** | 8.841 | 11.657 | 34.546 | 37.057 |
| `nbody` | 40.929 | 40.877 | **39.055** | 99.279 | 3358.910 |

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
| _(floor: empty program)_ | _2.597_ | _78.322_ | _**80.919**_ | _58.254_ | _59.612_ |
| `lcg` | 2.734 | 83.419 | **86.153** | 65.223 | 67.109 |
| `packet_classifier` | 2.820 | 85.293 | **88.113** | 66.637 | 67.958 |
| `ring_write` | 2.907 | 86.873 | **89.780** | 67.574 | 68.383 |
| `histogram_bins` | 2.967 | 89.950 | **92.917** | 69.335 | 71.273 |
| `prefix_scan` | 2.997 | 90.160 | **93.157** | 71.893 | 70.868 |
| `binary_search` | 3.126 | 89.757 | **92.883** | 69.356 | 74.543 |
| `sort_window` | 3.214 | 95.775 | **98.989** | 73.883 | 76.571 |
| `bloom_filter` | 3.338 | 94.471 | **97.809** | 74.863 | 73.706 |
| `hash_join` | 5.498 | 208.069 | **213.567** | 117.767 | 109.303 |
| `sieve` | 2.990 | 90.385 | **93.375** | 76.356 | 77.197 |
| `fib` | 2.764 | 83.049 | **85.813** | 64.764 | 66.336 |
| `collatz` | 2.914 | 87.242 | **90.156** | 66.610 | 68.280 |
| `matmul` | 3.230 | 94.425 | **97.655** | 78.123 | 90.840 |
| `json_parse` | 42.322 | 529.700 | **572.022** | 119.820 | 200.354 |
| `nbody` | 4.367 | 106.778 | **111.145** | 95.126 | 91.598 |

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
