# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-07T13:35:17Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `ca268a0fb0151fa56eb4f5a4a04de20ac5409fa1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37628996629 |
| NURL | `v0.70.0-28-gca268a0f` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
| Node | v22.23.3 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| NURL flags | `nurlc` → LLVM IR; `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` (ThinLTO backend at O3 — the standard `nurl.sh` release pipeline) |
| C flags | `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` — the identical pipeline, so neither column gets a backend the other lacks |
| Rust flags | `rustc -C opt-level=3` — rustc has no prelink/backend split; opt-level 3 is the `cargo build --release` default |
| Node / Python | `node` / `python3`, no flags |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.469_ | _1.454_ | _1.641_ | _22.836_ | _17.002_ |
| `lcg` | 39.162 | **39.152** | 39.274 | 1889.296 | 5076.653 |
| `packet_classifier` | **56.378** | 56.456 | 56.582 | 163.690 | 4210.032 |
| `ring_write` | 42.353 | **42.349** | 42.498 | 67.673 | 6548.583 |
| `histogram_bins` | **39.670** | 40.835 | 40.984 | 68.281 | 6076.403 |
| `prefix_scan` | 21.803 | **21.667** | 21.856 | 66.296 | 4504.458 |
| `binary_search` | 39.592 | **38.451** | 41.030 | 107.142 | 6393.249 |
| `sort_window` | **26.618** | 26.711 | 26.799 | 198.238 | 11701.599 |
| `bloom_filter` | **15.372** | 17.834 | 18.329 | 2822.912 | 7824.700 |
| `hash_join` | **26.809** | 28.154 | 29.287 | 3409.497 | 8282.051 |
| `sieve` | 20.847 | **19.884** | 20.201 | 67.779 | 3401.150 |
| `fib` | **25.055** | 29.760 | 30.002 | 132.325 | 1377.157 |
| `collatz` | 12.235 | **12.213** | 12.475 | 50.854 | 737.270 |
| `matmul` | 33.415 | **33.401** | 33.795 | 78.120 | 3449.311 |
| `json_parse` | **8.490** | 8.704 | 11.904 | 36.015 | 39.282 |
| `nbody` | **25.170** | 39.777 | 25.257 | 100.885 | 3060.522 |

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
| _(floor: empty program)_ | _3.616_ | _98.984_ | _**102.600**_ | _60.040_ | _77.546_ | _59.675_ |
| `lcg` | 3.678 | 111.293 | **114.971** | 60.045 | 89.522 | 66.804 |
| `packet_classifier` | 3.942 | 113.933 | **117.875** | 62.079 | 91.072 | 66.659 |
| `ring_write` | 3.921 | 116.086 | **120.007** | 63.113 | 94.083 | 69.554 |
| `histogram_bins` | 4.050 | 123.281 | **127.331** | 61.962 | 110.040 | 78.297 |
| `prefix_scan` | 4.200 | 115.674 | **119.874** | 62.341 | 96.799 | 71.629 |
| `binary_search` | 4.321 | 115.059 | **119.380** | 62.170 | 93.982 | 76.403 |
| `sort_window` | 4.473 | 115.882 | **120.355** | 61.389 | 103.758 | 79.886 |
| `bloom_filter` | 5.141 | 122.407 | **127.548** | 62.906 | 101.016 | 75.213 |
| `hash_join` | 8.939 | 263.657 | **272.596** | 65.613 | 220.246 | 122.604 |
| `sieve` | 4.281 | 116.208 | **120.489** | 63.780 | 104.053 | 80.862 |
| `fib` | 3.760 | 111.885 | **115.645** | 61.276 | 90.591 | 67.393 |
| `collatz` | 4.046 | 116.031 | **120.077** | 61.452 | 92.942 | 70.933 |
| `matmul` | 4.833 | 114.346 | **119.179** | 63.133 | 107.101 | 94.043 |
| `json_parse` | 48.809 | 484.629 | **533.438** | 108.578 | 164.287 | 171.813 |
| `nbody` | 6.854 | 132.352 | **139.206** | 63.990 | 127.261 | 105.073 |

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
