# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-02T22:00:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `b7fb6f76cc91cfe999724ffcabc1f67f29243d50` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30768967279 |
| NURL | `v0.31.1` |
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
| _(floor: empty program)_ | _1.646_ | _1.722_ | _1.862_ | _23.348_ | _17.416_ |
| `lcg` | 39.634 | **39.339** | 39.462 | 1875.990 | 5077.904 |
| `packet_classifier` | 56.663 | **56.432** | 56.713 | 162.463 | 4318.437 |
| `ring_write` | **42.325** | 42.690 | 42.756 | 67.318 | 6442.458 |
| `histogram_bins` | **39.770** | 41.448 | 40.018 | 66.772 | 6210.528 |
| `prefix_scan` | **21.962** | 22.022 | 22.207 | 65.237 | 4428.419 |
| `binary_search` | 39.935 | **38.576** | 43.236 | 106.840 | 6206.620 |
| `sort_window` | 27.285 | 27.607 | **26.895** | 199.470 | 11634.883 |
| `bloom_filter` | **18.066** | 18.249 | 18.508 | 2826.283 | 7762.643 |
| `hash_join` | **28.109** | 30.277 | 30.052 | 3428.871 | 8135.811 |
| `sieve` | 18.570 | 18.486 | **18.469** | 67.329 | 3266.296 |
| `fib` | **25.209** | 30.056 | 28.379 | 132.508 | 1349.473 |
| `collatz` | 12.475 | **12.451** | 12.670 | 49.808 | 710.860 |
| `matmul` | 33.759 | **33.550** | 33.771 | 75.985 | 3262.235 |
| `json_parse` | **8.683** | 8.843 | 11.812 | 36.109 | 37.402 |
| `nbody` | 40.841 | 40.923 | **39.062** | 99.877 | 3030.288 |

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
| _(floor: empty program)_ | _2.656_ | _80.203_ | _**82.859**_ | _56.748_ | _61.428_ |
| `lcg` | 2.693 | 83.681 | **86.374** | 65.611 | 69.359 |
| `packet_classifier` | 2.758 | 85.172 | **87.930** | 70.376 | 70.742 |
| `ring_write` | 2.901 | 87.121 | **90.022** | 67.754 | 70.965 |
| `histogram_bins` | 2.963 | 89.589 | **92.552** | 72.439 | 71.599 |
| `prefix_scan` | 2.956 | 90.611 | **93.567** | 72.159 | 71.551 |
| `binary_search` | 3.068 | 89.630 | **92.698** | 67.724 | 74.413 |
| `sort_window` | 3.154 | 97.062 | **100.216** | 74.456 | 81.276 |
| `bloom_filter` | 3.298 | 93.716 | **97.014** | 77.209 | 74.176 |
| `hash_join` | 5.338 | 211.300 | **216.638** | 120.622 | 111.215 |
| `sieve` | 3.007 | 93.139 | **96.146** | 78.467 | 81.118 |
| `fib` | 2.706 | 83.760 | **86.466** | 65.710 | 67.147 |
| `collatz` | 2.839 | 87.877 | **90.716** | 67.305 | 70.580 |
| `matmul` | 3.206 | 95.435 | **98.641** | 79.734 | 91.782 |
| `json_parse` | 39.931 | 512.004 | **551.935** | 122.218 | 178.513 |
| `nbody` | 4.233 | 105.998 | **110.231** | 95.977 | 92.075 |

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
