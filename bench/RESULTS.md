# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T12:31:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `4dad7cbbea4316444845299550a75e67b3c210f6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30630571522 |
| NURL | `v0.29.0-87-g4dad7cb` |
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
| _(floor: empty program)_ | _1.861_ | _1.903_ | _2.060_ | _26.575_ | _18.879_ |
| `lcg` | **44.365** | 44.415 | 44.582 | 1829.774 | 5481.592 |
| `packet_classifier` | 63.866 | **63.835** | 64.115 | 159.912 | 4562.948 |
| `ring_write` | **47.921** | 48.049 | 48.088 | 73.237 | 6535.754 |
| `histogram_bins` | **44.853** | 44.982 | 45.096 | 76.157 | 6337.171 |
| `prefix_scan` | **24.682** | 24.732 | 24.922 | 71.354 | 4766.712 |
| `binary_search` | **35.994** | 36.215 | 46.452 | 111.723 | 6913.111 |
| `sort_window` | 31.070 | 31.159 | **30.590** | 164.683 | 11709.871 |
| `bloom_filter` | **19.970** | 20.766 | 21.050 | 2774.676 | 8016.307 |
| `hash_join` | **29.421** | 31.095 | 31.482 | 3418.093 | 8166.072 |
| `sieve` | 20.566 | **20.564** | 20.623 | 71.600 | 3492.829 |
| `fib` | **28.164** | 33.417 | 29.588 | 142.567 | 1294.737 |
| `collatz` | 13.940 | **13.938** | 14.067 | 53.306 | 750.053 |
| `matmul` | 45.804 | 46.633 | **45.688** | 88.446 | 4046.524 |
| `json_parse` | **8.474** | 9.358 | 12.641 | 40.501 | 38.367 |
| `nbody` | 46.899 | 46.890 | **44.912** | 97.464 | 3153.210 |

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
| _(floor: empty program)_ | _3.394_ | _93.043_ | _**96.437**_ | _67.888_ | _71.035_ |
| `lcg` | 3.576 | 95.667 | **99.243** | 74.798 | 74.687 |
| `packet_classifier` | 3.783 | 99.871 | **103.654** | 73.924 | 74.237 |
| `ring_write` | 3.970 | 100.268 | **104.238** | 79.066 | 80.495 |
| `histogram_bins` | 4.127 | 102.208 | **106.335** | 77.996 | 78.441 |
| `prefix_scan` | 4.139 | 100.031 | **104.170** | 80.221 | 77.924 |
| `binary_search` | 4.459 | 99.131 | **103.590** | 76.931 | 83.808 |
| `sort_window` | 4.587 | 106.279 | **110.866** | 83.122 | 90.834 |
| `bloom_filter` | 4.825 | 107.239 | **112.064** | 82.788 | 82.993 |
| `hash_join` | 9.669 | 211.215 | **220.884** | 128.151 | 118.756 |
| `sieve` | 4.252 | 104.373 | **108.625** | 86.788 | 85.586 |
| `fib` | 3.593 | 92.990 | **96.583** | 73.305 | 74.281 |
| `collatz` | 4.053 | 99.076 | **103.129** | 75.154 | 79.135 |
| `matmul` | 4.881 | 108.549 | **113.430** | 90.293 | 98.698 |
| `json_parse` | 78.016 | 712.231 | **790.247** | 129.874 | 199.093 |
| `nbody` | 7.400 | 120.162 | **127.562** | 101.902 | 101.169 |

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
