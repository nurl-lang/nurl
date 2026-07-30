# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T13:28:23Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373464 KiB |
| Commit | `fc44ce7edef30384bbde6fc05eeb10fa759ef1e3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30546683449 |
| NURL | `v0.29.0-28-gfc44ce7` |
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
| _(floor: empty program)_ | _1.675_ | _1.695_ | _1.842_ | _21.464_ | _17.143_ |
| `lcg` | **39.195** | 39.213 | 39.369 | 1875.214 | 5078.648 |
| `packet_classifier` | **56.594** | 56.654 | 56.808 | 161.805 | 4540.617 |
| `ring_write` | 42.433 | **42.370** | 42.477 | 64.995 | 6768.056 |
| `histogram_bins` | **39.594** | 41.314 | 39.806 | 64.539 | 6021.638 |
| `prefix_scan` | **21.868** | 21.911 | 22.038 | 65.232 | 4552.529 |
| `binary_search` | 40.178 | **38.493** | 43.299 | 105.634 | 6376.640 |
| `sort_window` | 27.456 | 27.371 | **26.896** | 197.364 | 11465.989 |
| `bloom_filter` | **17.982** | 18.153 | 18.517 | 2830.430 | 7423.186 |
| `hash_join` | **28.109** | 30.154 | 29.927 | 3451.811 | 8285.677 |
| `sieve` | 18.594 | 18.468 | **18.207** | 64.888 | 3286.028 |
| `fib` | **25.272** | 30.001 | 28.473 | 130.670 | 1348.629 |
| `collatz` | **12.478** | 12.522 | 12.538 | 49.185 | 709.830 |
| `matmul` | **33.558** | 33.608 | 33.789 | 76.177 | 3289.677 |
| `json_parse` | **8.525** | 8.958 | 11.799 | 35.809 | 37.495 |
| `nbody` | 40.906 | 40.817 | **38.956** | 100.147 | 3042.344 |

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
| _(floor: empty program)_ | _3.030_ | _78.139_ | _**81.169**_ | _55.906_ | _60.173_ |
| `lcg` | 3.188 | 82.881 | **86.069** | 65.064 | 67.669 |
| `packet_classifier` | 3.398 | 88.031 | **91.429** | 70.759 | 70.483 |
| `ring_write` | 3.489 | 85.688 | **89.177** | 69.566 | 69.516 |
| `histogram_bins` | 3.587 | 88.929 | **92.516** | 69.543 | 76.373 |
| `prefix_scan` | 3.637 | 90.121 | **93.758** | 71.686 | 70.090 |
| `binary_search` | 3.858 | 88.445 | **92.303** | 68.940 | 74.411 |
| `sort_window` | 4.039 | 95.630 | **99.669** | 74.711 | 79.590 |
| `bloom_filter` | 4.406 | 94.678 | **99.084** | 76.078 | 73.990 |
| `hash_join` | 8.651 | 210.659 | **219.310** | 120.757 | 110.063 |
| `sieve` | 3.792 | 90.099 | **93.891** | 77.567 | 77.702 |
| `fib` | 3.207 | 83.300 | **86.507** | 65.308 | 67.707 |
| `collatz` | 3.513 | 85.905 | **89.418** | 67.370 | 69.249 |
| `matmul` | 4.311 | 94.448 | **98.759** | 82.030 | 91.188 |
| `json_parse` | 73.607 | 729.877 | **803.484** | 125.306 | 178.346 |
| `nbody` | 6.689 | 105.856 | **112.545** | 97.899 | 91.753 |

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
