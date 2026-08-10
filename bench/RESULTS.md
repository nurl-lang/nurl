# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-10T21:46:03Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ea3a0dfc210865ccfecfe1aa0eab7c31322b6467` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31434982303 |
| NURL | `v0.36.0-84-gea3a0dfc` |
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
| _(floor: empty program)_ | _1.662_ | _1.745_ | _1.870_ | _24.013_ | _16.740_ |
| `lcg` | **39.244** | 39.306 | 39.413 | 1880.550 | 5191.262 |
| `packet_classifier` | 56.679 | **56.528** | 56.689 | 163.153 | 4509.867 |
| `ring_write` | 42.495 | **42.457** | 42.643 | 65.691 | 6490.644 |
| `histogram_bins` | **39.758** | 41.432 | 39.966 | 67.611 | 6196.722 |
| `prefix_scan` | **21.851** | 21.916 | 22.066 | 65.031 | 4472.406 |
| `binary_search` | 39.944 | **39.180** | 43.344 | 107.172 | 6106.853 |
| `sort_window` | 27.438 | 27.484 | **26.931** | 197.591 | 12954.143 |
| `bloom_filter` | **18.120** | 18.267 | 18.507 | 2838.142 | 7535.147 |
| `hash_join` | **28.159** | 30.157 | 30.125 | 3440.788 | 8222.514 |
| `sieve` | 20.548 | 20.505 | **20.307** | 66.540 | 3255.202 |
| `fib` | **25.401** | 30.245 | 28.357 | 130.945 | 1367.274 |
| `collatz` | **12.538** | 12.543 | 12.599 | 49.648 | 715.093 |
| `matmul` | **33.459** | 33.614 | 33.769 | 75.759 | 3438.945 |
| `json_parse` | 42.370 | **8.874** | 11.848 | 35.801 | 37.308 |
| `nbody` | 41.031 | 41.224 | **40.278** | 101.942 | 3162.617 |

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
| _(floor: empty program)_ | _2.664_ | _79.557_ | _**82.221**_ | _56.192_ | _59.799_ |
| `lcg` | 2.783 | 86.118 | **88.901** | 66.396 | 67.492 |
| `packet_classifier` | 2.853 | 86.799 | **89.652** | 67.029 | 67.321 |
| `ring_write` | 2.998 | 89.115 | **92.113** | 67.511 | 71.103 |
| `histogram_bins` | 3.013 | 92.363 | **95.376** | 70.830 | 72.761 |
| `prefix_scan` | 3.027 | 92.417 | **95.444** | 71.608 | 70.807 |
| `binary_search` | 3.236 | 90.662 | **93.898** | 69.559 | 74.854 |
| `sort_window` | 3.284 | 101.071 | **104.355** | 77.411 | 78.849 |
| `bloom_filter` | 3.453 | 97.173 | **100.626** | 78.246 | 74.457 |
| `hash_join` | 5.585 | 212.706 | **218.291** | 119.832 | 109.589 |
| `sieve` | 3.063 | 92.769 | **95.832** | 78.659 | 80.429 |
| `fib` | 2.879 | 87.143 | **90.022** | 67.358 | 67.563 |
| `collatz` | 3.006 | 91.014 | **94.020** | 69.132 | 71.845 |
| `matmul` | 3.352 | 99.960 | **103.312** | 81.288 | 91.900 |
| `json_parse` | 42.586 | 544.766 | **587.352** | 124.367 | 176.639 |
| `nbody` | 4.356 | 107.711 | **112.067** | 96.027 | 92.246 |

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
