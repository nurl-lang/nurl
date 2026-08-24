# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-24T07:28:51Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `948fbb197a9f23d814047bc325624e63512e22e9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32701366455 |
| NURL | `v0.50.0-5-g948fbb19` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
| Node | v22.23.2 |
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
| _(floor: empty program)_ | _1.116_ | _1.112_ | _1.317_ | _20.674_ | _14.111_ |
| `lcg` | 35.763 | **35.380** | 35.514 | 1408.926 | 3815.964 |
| `packet_classifier` | 60.718 | 61.056 | **60.343** | 151.665 | 3065.413 |
| `ring_write` | **39.053** | 39.154 | 40.603 | 59.615 | 4534.788 |
| `histogram_bins` | **36.550** | 36.650 | 39.945 | 63.384 | 4381.559 |
| `prefix_scan` | 19.595 | **19.447** | 19.963 | 60.946 | 3336.919 |
| `binary_search` | **24.309** | 28.345 | 26.945 | 100.140 | 4977.772 |
| `sort_window` | **35.701** | 36.180 | 36.089 | 164.156 | 8301.023 |
| `bloom_filter` | 12.663 | **12.299** | 13.067 | 2227.771 | 6253.147 |
| `hash_join` | **21.258** | 22.526 | 22.439 | 2757.128 | 6309.731 |
| `sieve` | 32.312 | **32.141** | 33.278 | 78.830 | 2379.838 |
| `fib` | **25.476** | 27.343 | 26.283 | 102.723 | 808.949 |
| `collatz` | **13.563** | 14.230 | 14.576 | 54.572 | 515.274 |
| `matmul` | 18.139 | **17.926** | 18.121 | 67.940 | 2231.370 |
| `json_parse` | **6.894** | 6.968 | 8.758 | 32.001 | 30.895 |
| `nbody` | **19.552** | 27.913 | 19.879 | 73.100 | 1919.673 |

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
| _(floor: empty program)_ | _2.150_ | _73.159_ | _**75.309**_ | _48.213_ | _62.847_ | _49.027_ |
| `lcg` | 2.335 | 75.319 | **77.654** | 47.095 | 68.778 | 55.640 |
| `packet_classifier` | 2.426 | 74.452 | **76.878** | 45.311 | 70.091 | 51.742 |
| `ring_write` | 2.447 | 76.814 | **79.261** | 45.615 | 75.013 | 56.528 |
| `histogram_bins` | 2.555 | 90.811 | **93.366** | 46.023 | 85.428 | 64.057 |
| `prefix_scan` | 2.652 | 78.802 | **81.454** | 47.511 | 75.289 | 58.023 |
| `binary_search` | 2.689 | 84.022 | **86.711** | 47.279 | 73.368 | 59.675 |
| `sort_window` | 2.738 | 85.154 | **87.892** | 48.546 | 81.228 | 66.935 |
| `bloom_filter` | 3.076 | 85.275 | **88.351** | 47.734 | 77.537 | 59.985 |
| `hash_join` | 4.994 | 200.815 | **205.809** | 50.039 | 169.812 | 105.021 |
| `sieve` | 2.603 | 80.684 | **83.287** | 49.118 | 79.503 | 66.965 |
| `fib` | 2.341 | 78.370 | **80.711** | 48.599 | 70.523 | 54.134 |
| `collatz` | 2.558 | 79.145 | **81.703** | 46.824 | 70.077 | 58.049 |
| `matmul` | 2.846 | 83.591 | **86.437** | 47.603 | 83.056 | 79.106 |
| `json_parse` | 45.198 | 337.785 | **382.983** | 92.507 | 124.344 | 158.956 |
| `nbody` | 3.847 | 102.387 | **106.234** | 49.249 | 98.819 | 84.149 |

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
