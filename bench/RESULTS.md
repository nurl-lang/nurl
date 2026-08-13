# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T11:55:32Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `25f11434db56ee8640d1dfe04de97a849a3505dd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31697303472 |
| NURL | `v0.40.0` |
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
| _(floor: empty program)_ | _1.832_ | _1.881_ | _2.074_ | _23.716_ | _17.923_ |
| `lcg` | **44.300** | 44.431 | 44.509 | 1835.251 | 5543.269 |
| `packet_classifier` | **63.756** | 63.830 | 63.966 | 158.528 | 4822.004 |
| `ring_write` | **47.928** | 47.971 | 48.083 | 73.400 | 7238.115 |
| `histogram_bins` | 44.979 | **44.929** | 45.097 | 75.533 | 6281.555 |
| `prefix_scan` | **24.715** | 24.800 | 24.906 | 72.100 | 4935.738 |
| `binary_search` | **34.309** | 35.817 | 46.108 | 112.175 | 6695.187 |
| `sort_window` | **30.330** | 31.099 | 30.558 | 169.941 | 12053.506 |
| `bloom_filter` | **20.216** | 20.817 | 20.920 | 2808.648 | 7671.251 |
| `hash_join` | **28.116** | 31.153 | 31.932 | 3456.367 | 8212.164 |
| `sieve` | 20.560 | **20.250** | 20.570 | 72.055 | 3527.237 |
| `fib` | **28.152** | 33.438 | 29.512 | 143.035 | 1293.974 |
| `collatz` | **13.959** | 14.140 | 14.402 | 54.652 | 752.912 |
| `matmul` | **45.723** | 45.885 | 46.409 | 83.510 | 3450.246 |
| `json_parse` | **8.950** | 9.110 | 12.476 | 38.592 | 39.072 |
| `nbody` | **26.993** | 46.392 | 44.323 | 97.053 | 3303.854 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns: a cold compile, measured
against a wiped cache exactly as C and Rust pay their full cost every
time. **NURL rebuild** is the same compile again with the ThinLTO
cache warm — `nurl.sh`'s default on Linux (docs/BUILDING.md → The
ThinLTO cache) — which is what every build after the first costs; C
and Rust have no default equivalent (`ccache`/`sccache` are opt-in
add-ons). The floor row is what each toolchain costs for a program
that does nothing — for NURL that is dominated by the LTO link every
NURL binary pays for, so subtract it to read the marginal cost of the
benchmark itself. Node and Python have no column here: they compile
at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | NURL rebuild | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.073_ | _100.082_ | _**103.155**_ | _65.032_ | _64.315_ | _65.501_ |
| `lcg` | 3.252 | 103.664 | **106.916** | 65.420 | 73.808 | 73.036 |
| `packet_classifier` | 3.318 | 104.410 | **107.728** | 65.194 | 73.827 | 74.492 |
| `ring_write` | 3.323 | 102.481 | **105.804** | 64.969 | 74.924 | 75.174 |
| `histogram_bins` | 3.481 | 123.854 | **127.335** | 66.740 | 78.726 | 78.022 |
| `prefix_scan` | 3.561 | 112.108 | **115.669** | 67.600 | 82.217 | 79.515 |
| `binary_search` | 3.612 | 112.676 | **116.288** | 65.598 | 76.219 | 81.409 |
| `sort_window` | 3.759 | 120.132 | **123.891** | 68.299 | 85.917 | 86.692 |
| `bloom_filter` | 4.033 | 117.075 | **121.108** | 69.648 | 87.907 | 90.450 |
| `hash_join` | 6.413 | 263.551 | **269.964** | 72.326 | 127.048 | 125.743 |
| `sieve` | 3.514 | 107.469 | **110.983** | 65.536 | 85.054 | 86.283 |
| `fib` | 3.294 | 102.911 | **106.205** | 65.520 | 75.623 | 73.296 |
| `collatz` | 3.353 | 104.922 | **108.275** | 65.632 | 75.084 | 77.036 |
| `matmul` | 3.763 | 111.787 | **115.550** | 66.069 | 86.860 | 99.470 |
| `json_parse` | 45.860 | 419.332 | **465.192** | 110.383 | 129.941 | 188.019 |
| `nbody` | 4.901 | 133.359 | **138.260** | 67.363 | 101.323 | 100.245 |

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
