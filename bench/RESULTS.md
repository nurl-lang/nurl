# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T11:37:51Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `2456ae5887a1916c78228a87e1471ddc6479bdd5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30538978349 |
| NURL | `v0.29.0-15-g2456ae5` |
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
| _(floor: empty program)_ | _1.696_ | _1.751_ | _1.892_ | _22.629_ | _17.085_ |
| `lcg` | **39.152** | 39.301 | 39.493 | 1873.733 | 5176.249 |
| `packet_classifier` | **56.300** | 56.464 | 56.579 | 161.230 | 4303.031 |
| `ring_write` | **42.346** | 42.444 | 42.538 | 67.151 | 6188.614 |
| `histogram_bins` | **39.664** | 41.446 | 40.034 | 67.130 | 6141.954 |
| `prefix_scan` | **21.836** | 21.927 | 22.070 | 65.303 | 4550.495 |
| `binary_search` | 39.750 | **38.392** | 43.413 | 106.690 | 6129.914 |
| `sort_window` | 27.324 | 27.412 | **26.905** | 197.637 | 11447.151 |
| `bloom_filter` | **18.031** | 18.233 | 18.627 | 2882.118 | 7438.348 |
| `hash_join` | **28.293** | 30.333 | 30.205 | 3452.162 | 8214.372 |
| `sieve` | 21.080 | **19.968** | 20.020 | 67.450 | 3333.764 |
| `fib` | **25.256** | 30.017 | 28.238 | 132.779 | 1371.315 |
| `collatz` | 12.443 | **12.428** | 12.524 | 49.559 | 710.228 |
| `matmul` | 33.899 | 33.941 | **33.812** | 75.878 | 4893.794 |
| `json_parse` | **8.596** | 8.923 | 11.945 | 37.376 | 38.406 |
| `nbody` | 40.881 | 42.093 | **39.284** | 101.027 | 2954.795 |

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
| _(floor: empty program)_ | _3.068_ | _80.873_ | _**83.941**_ | _58.705_ | _60.770_ |
| `lcg` | 3.089 | 84.957 | **88.046** | 65.848 | 67.326 |
| `packet_classifier` | 3.169 | 88.349 | **91.518** | 67.865 | 68.693 |
| `ring_write` | 3.427 | 90.373 | **93.800** | 71.025 | 70.121 |
| `histogram_bins` | 3.538 | 92.859 | **96.397** | 72.274 | 73.409 |
| `prefix_scan` | 3.580 | 93.310 | **96.890** | 73.122 | 72.870 |
| `binary_search` | 3.859 | 93.153 | **97.012** | 71.508 | 75.914 |
| `sort_window` | 3.992 | 99.926 | **103.918** | 76.979 | 80.681 |
| `bloom_filter` | 4.182 | 97.099 | **101.281** | 79.467 | 76.973 |
| `hash_join` | 8.546 | 214.367 | **222.913** | 121.767 | 112.439 |
| `sieve` | 3.666 | 93.110 | **96.776** | 80.668 | 80.604 |
| `fib` | 3.094 | 86.653 | **89.747** | 68.977 | 67.789 |
| `collatz` | 3.520 | 93.103 | **96.623** | 72.040 | 72.184 |
| `matmul` | 4.289 | 100.128 | **104.417** | 82.288 | 92.484 |
| `json_parse` | 71.573 | 737.907 | **809.480** | 125.479 | 180.837 |
| `nbody` | 6.624 | 111.996 | **118.620** | 101.349 | 94.684 |

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
