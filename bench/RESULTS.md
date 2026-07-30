# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T16:22:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d831d559703ef502db02d19f122394892a056ebd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30560783605 |
| NURL | `v0.29.0-37-gd831d55` |
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
| _(floor: empty program)_ | _1.669_ | _1.712_ | _1.847_ | _22.511_ | _17.005_ |
| `lcg` | **39.211** | 39.227 | 39.431 | 1875.341 | 5081.112 |
| `packet_classifier` | **56.452** | 56.514 | 56.597 | 161.291 | 4705.944 |
| `ring_write` | **42.352** | 42.478 | 42.471 | 63.797 | 6829.039 |
| `histogram_bins` | **39.670** | 41.362 | 39.970 | 66.278 | 6105.015 |
| `prefix_scan` | **21.855** | 21.934 | 22.036 | 64.460 | 4487.654 |
| `binary_search` | 39.916 | **38.534** | 43.187 | 105.131 | 6377.801 |
| `sort_window` | 27.393 | 27.478 | **26.885** | 196.534 | 11444.132 |
| `bloom_filter` | **18.046** | 18.267 | 18.560 | 2838.243 | 7707.094 |
| `hash_join` | **28.008** | 30.190 | 29.991 | 3409.988 | 8150.001 |
| `sieve` | 18.949 | 19.840 | **18.068** | 64.932 | 3255.495 |
| `fib` | **25.308** | 30.040 | 28.356 | 129.985 | 1357.616 |
| `collatz` | **12.470** | 12.532 | 12.547 | 48.018 | 710.584 |
| `matmul` | 33.508 | **33.491** | 33.761 | 75.504 | 3097.314 |
| `json_parse` | **8.500** | 8.876 | 11.776 | 35.747 | 37.659 |
| `nbody` | 40.927 | 40.960 | **39.059** | 100.103 | 3130.072 |

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
| _(floor: empty program)_ | _3.103_ | _80.661_ | _**83.764**_ | _59.176_ | _61.994_ |
| `lcg` | 3.132 | 85.112 | **88.244** | 67.388 | 68.140 |
| `packet_classifier` | 3.271 | 85.620 | **88.891** | 68.857 | 68.694 |
| `ring_write` | 3.489 | 85.409 | **88.898** | 67.584 | 70.012 |
| `histogram_bins` | 3.561 | 88.497 | **92.058** | 69.820 | 71.389 |
| `prefix_scan` | 3.652 | 89.290 | **92.942** | 71.299 | 70.833 |
| `binary_search` | 3.925 | 88.224 | **92.149** | 67.801 | 73.458 |
| `sort_window` | 4.008 | 94.516 | **98.524** | 74.073 | 78.344 |
| `bloom_filter` | 4.306 | 94.437 | **98.743** | 76.811 | 74.730 |
| `hash_join` | 8.687 | 208.598 | **217.285** | 118.611 | 112.422 |
| `sieve` | 3.719 | 90.781 | **94.500** | 78.656 | 78.378 |
| `fib` | 3.146 | 82.159 | **85.305** | 64.891 | 66.557 |
| `collatz` | 3.485 | 86.267 | **89.752** | 66.356 | 69.117 |
| `matmul` | 4.356 | 93.927 | **98.283** | 78.869 | 95.877 |
| `json_parse` | 74.789 | 720.333 | **795.122** | 122.734 | 177.739 |
| `nbody` | 6.672 | 104.543 | **111.215** | 95.614 | 91.239 |

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
