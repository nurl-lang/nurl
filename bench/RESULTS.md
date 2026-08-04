# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-04T17:35:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ecdcce8f63891d4dce30df08065859aff9b362ef` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30934276677 |
| NURL | `v0.32.0-41-gecdcce8f` |
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
| _(floor: empty program)_ | _1.643_ | _1.698_ | _1.836_ | _23.269_ | _16.947_ |
| `lcg` | 39.415 | **39.317** | 39.503 | 1878.628 | 5072.816 |
| `packet_classifier` | **56.625** | 56.699 | 56.913 | 162.513 | 4285.412 |
| `ring_write` | **42.460** | 42.716 | 42.591 | 66.931 | 6474.676 |
| `histogram_bins` | **39.767** | 41.413 | 39.934 | 67.234 | 6172.737 |
| `prefix_scan` | **21.850** | 21.998 | 22.114 | 66.315 | 4845.331 |
| `binary_search` | 40.019 | **38.678** | 43.386 | 109.362 | 5831.004 |
| `sort_window` | 27.446 | 27.463 | **26.979** | 199.056 | 12324.049 |
| `bloom_filter` | **18.129** | 18.354 | 18.705 | 2826.543 | 7479.381 |
| `hash_join` | **28.102** | 30.215 | 30.139 | 3494.941 | 8511.299 |
| `sieve` | 18.524 | **17.899** | 18.448 | 66.068 | 3273.334 |
| `fib` | **25.394** | 29.953 | 28.229 | 131.278 | 1354.212 |
| `collatz` | 12.453 | **12.439** | 12.584 | 49.248 | 724.247 |
| `matmul` | 33.896 | **33.557** | 33.845 | 76.798 | 3313.484 |
| `json_parse` | **8.738** | 8.876 | 11.847 | 37.814 | 39.074 |
| `nbody` | 41.105 | 41.091 | **39.245** | 103.410 | 2994.053 |

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
| _(floor: empty program)_ | _2.940_ | _87.945_ | _**90.885**_ | _62.737_ | _60.883_ |
| `lcg` | 2.798 | 89.352 | **92.150** | 71.759 | 72.179 |
| `packet_classifier` | 3.055 | 91.364 | **94.419** | 72.084 | 72.846 |
| `ring_write` | 2.967 | 95.492 | **98.459** | 69.697 | 69.127 |
| `histogram_bins` | 3.098 | 96.328 | **99.426** | 75.174 | 81.719 |
| `prefix_scan` | 3.024 | 96.327 | **99.351** | 78.552 | 77.691 |
| `binary_search` | 3.165 | 96.516 | **99.681** | 74.210 | 74.818 |
| `sort_window` | 3.206 | 104.651 | **107.857** | 77.256 | 78.075 |
| `bloom_filter` | 3.435 | 107.417 | **110.852** | 79.286 | 76.981 |
| `hash_join` | 5.455 | 223.457 | **228.912** | 126.497 | 114.917 |
| `sieve` | 3.037 | 98.922 | **101.959** | 79.079 | 80.298 |
| `fib` | 2.761 | 84.823 | **87.584** | 69.067 | 68.813 |
| `collatz` | 2.950 | 91.443 | **94.393** | 70.585 | 72.926 |
| `matmul` | 3.264 | 99.368 | **102.632** | 79.679 | 93.955 |
| `json_parse` | 40.206 | 525.167 | **565.373** | 123.033 | 185.171 |
| `nbody` | 4.366 | 117.227 | **121.593** | 97.581 | 97.035 |

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
