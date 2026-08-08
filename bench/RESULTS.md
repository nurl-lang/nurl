# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T21:12:02Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `cccb7a23752fa935bbb9a3d1fb762cf3b5981f81` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31278543737 |
| NURL | `v0.36.0-5-gcccb7a23` |
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
| _(floor: empty program)_ | _1.673_ | _1.740_ | _1.874_ | _23.962_ | _18.119_ |
| `lcg` | **39.399** | 39.596 | 39.646 | 1899.724 | 5062.864 |
| `packet_classifier` | **56.789** | 56.814 | 56.928 | 163.483 | 4514.182 |
| `ring_write` | **42.485** | 42.968 | 43.212 | 67.280 | 6705.880 |
| `histogram_bins` | **39.915** | 41.551 | 40.154 | 68.000 | 6052.422 |
| `prefix_scan` | **22.092** | 22.247 | 22.377 | 66.052 | 4456.505 |
| `binary_search` | 40.117 | **38.606** | 43.605 | 107.986 | 6221.560 |
| `sort_window` | 27.423 | 27.560 | **26.935** | 198.117 | 11184.867 |
| `bloom_filter` | **18.118** | 18.283 | 18.552 | 2843.560 | 7762.664 |
| `hash_join` | **28.118** | 30.233 | 29.996 | 3409.082 | 8160.866 |
| `sieve` | 18.652 | 20.048 | **18.606** | 66.577 | 3407.506 |
| `fib` | **25.260** | 30.038 | 28.294 | 130.738 | 1362.412 |
| `collatz` | 12.487 | **12.462** | 12.627 | 48.587 | 712.242 |
| `matmul` | 33.894 | **33.877** | 34.095 | 78.084 | 3212.604 |
| `json_parse` | 42.377 | **8.895** | 11.850 | 36.579 | 37.909 |
| `nbody` | 41.087 | 41.060 | **39.271** | 100.210 | 3082.706 |

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
| _(floor: empty program)_ | _2.747_ | _82.970_ | _**85.717**_ | _59.501_ | _61.870_ |
| `lcg` | 2.945 | 89.089 | **92.034** | 69.496 | 70.368 |
| `packet_classifier` | 2.889 | 89.972 | **92.861** | 68.691 | 68.423 |
| `ring_write` | 3.015 | 91.486 | **94.501** | 70.345 | 69.909 |
| `histogram_bins` | 3.111 | 94.011 | **97.122** | 71.148 | 72.879 |
| `prefix_scan` | 3.065 | 94.632 | **97.697** | 74.810 | 72.333 |
| `binary_search` | 3.335 | 94.303 | **97.638** | 70.909 | 76.241 |
| `sort_window` | 3.345 | 100.103 | **103.448** | 76.321 | 96.089 |
| `bloom_filter` | 3.383 | 96.106 | **99.489** | 78.599 | 74.874 |
| `hash_join` | 5.599 | 213.681 | **219.280** | 120.590 | 131.439 |
| `sieve` | 3.086 | 90.909 | **93.995** | 77.398 | 78.307 |
| `fib` | 2.791 | 85.523 | **88.314** | 65.738 | 65.664 |
| `collatz` | 3.034 | 93.200 | **96.234** | 87.096 | 82.173 |
| `matmul` | 3.321 | 97.745 | **101.066** | 82.895 | 91.719 |
| `json_parse` | 41.971 | 542.181 | **584.152** | 125.577 | 180.242 |
| `nbody` | 4.593 | 110.186 | **114.779** | 98.121 | 93.950 |

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
