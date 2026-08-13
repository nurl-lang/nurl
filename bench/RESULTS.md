# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T04:35:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `2095851a957b16c5fc5c4acc272b20db069b57aa` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31667279922 |
| NURL | `v0.39.0-25-g2095851a` |
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
| _(floor: empty program)_ | _1.670_ | _1.737_ | _1.847_ | _22.538_ | _17.101_ |
| `lcg` | 39.391 | **39.308** | 39.409 | 1882.175 | 5240.355 |
| `packet_classifier` | 57.101 | **56.510** | 56.596 | 161.294 | 4586.551 |
| `ring_write` | **42.430** | 42.445 | 42.578 | 65.808 | 6359.832 |
| `histogram_bins` | **39.728** | 41.370 | 39.852 | 67.388 | 6039.811 |
| `prefix_scan` | 21.929 | **21.923** | 22.057 | 65.728 | 4472.472 |
| `binary_search` | 39.987 | **38.560** | 43.302 | 104.927 | 5919.615 |
| `sort_window` | 27.446 | 27.403 | **26.971** | 196.795 | 12060.359 |
| `bloom_filter` | **17.993** | 18.280 | 18.522 | 2820.540 | 8015.183 |
| `hash_join` | **28.224** | 30.291 | 30.192 | 3436.146 | 8377.514 |
| `sieve` | 19.006 | 18.459 | **17.985** | 65.756 | 3153.221 |
| `fib` | **25.333** | 30.076 | 28.281 | 130.712 | 1346.801 |
| `collatz` | **12.396** | 12.518 | 12.646 | 49.130 | 715.742 |
| `matmul` | 33.651 | **33.521** | 33.700 | 75.680 | 3300.610 |
| `json_parse` | 8.960 | **8.853** | 11.746 | 36.094 | 37.842 |
| `nbody` | 41.219 | 42.364 | **39.113** | 100.283 | 3139.161 |

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
| _(floor: empty program)_ | _2.647_ | _80.944_ | _**83.591**_ | _57.327_ | _59.750_ |
| `lcg` | 2.825 | 84.757 | **87.582** | 65.135 | 66.806 |
| `packet_classifier` | 2.885 | 86.012 | **88.897** | 65.920 | 67.686 |
| `ring_write` | 3.000 | 87.206 | **90.206** | 67.725 | 69.134 |
| `histogram_bins` | 3.071 | 93.241 | **96.312** | 70.752 | 72.079 |
| `prefix_scan` | 3.098 | 92.576 | **95.674** | 71.450 | 72.858 |
| `binary_search` | 3.215 | 89.978 | **93.193** | 69.089 | 74.326 |
| `sort_window` | 3.324 | 97.174 | **100.498** | 74.349 | 77.160 |
| `bloom_filter` | 3.458 | 96.286 | **99.744** | 76.330 | 73.558 |
| `hash_join` | 5.642 | 213.442 | **219.084** | 121.361 | 110.839 |
| `sieve` | 3.111 | 90.842 | **93.953** | 81.366 | 78.873 |
| `fib` | 2.793 | 82.840 | **85.633** | 65.442 | 67.078 |
| `collatz` | 3.021 | 90.049 | **93.070** | 67.335 | 68.869 |
| `matmul` | 3.484 | 102.319 | **105.803** | 84.789 | 93.326 |
| `json_parse` | 43.453 | 538.209 | **581.662** | 123.554 | 180.219 |
| `nbody` | 4.412 | 107.270 | **111.682** | 95.650 | 91.401 |

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
