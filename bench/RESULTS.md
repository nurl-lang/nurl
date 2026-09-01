# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-01T08:42:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `8f152ab387c490af7a940fad74212638ceb1a61d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33488021049 |
| NURL | `v0.57.0-15-g8f152ab3` |
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
| _(floor: empty program)_ | _1.519_ | _1.494_ | _1.762_ | _24.735_ | _18.351_ |
| `lcg` | 39.220 | **39.075** | 39.371 | 2045.456 | 5158.406 |
| `packet_classifier` | **56.353** | 56.439 | 56.583 | 163.714 | 4464.609 |
| `ring_write` | 42.386 | **42.327** | 42.626 | 69.542 | 6259.609 |
| `histogram_bins` | **39.714** | 40.838 | 39.968 | 68.960 | 6280.585 |
| `prefix_scan` | **21.741** | 21.845 | 22.007 | 68.650 | 4768.111 |
| `binary_search` | 39.807 | 38.375 | **37.243** | 108.923 | 5866.747 |
| `sort_window` | 26.644 | **26.578** | 27.034 | 197.900 | 11870.791 |
| `bloom_filter` | 17.990 | **17.970** | 18.504 | 2854.607 | 7452.931 |
| `hash_join` | **26.886** | 28.061 | 29.389 | 3416.707 | 8206.441 |
| `sieve` | 18.214 | **17.692** | 18.003 | 66.156 | 3293.078 |
| `fib` | 25.440 | 29.728 | **25.303** | 134.279 | 1374.796 |
| `collatz` | 12.228 | **12.196** | 12.364 | 48.539 | 722.784 |
| `matmul` | 81.559 | **33.175** | 41.100 | 76.399 | 3211.370 |
| `json_parse` | 8.765 | **8.514** | 11.586 | 35.463 | 37.798 |
| `nbody` | 25.249 | 39.781 | **24.228** | 101.068 | 2987.386 |

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
| _(floor: empty program)_ | _2.832_ | _102.315_ | _**105.147**_ | _61.086_ | _84.595_ | _63.529_ |
| `lcg` | 2.919 | 113.196 | **116.115** | 61.395 | 94.764 | 73.396 |
| `packet_classifier` | 2.856 | 108.583 | **111.439** | 59.252 | 92.476 | 70.269 |
| `ring_write` | 3.055 | 109.393 | **112.448** | 60.560 | 94.526 | 73.481 |
| `histogram_bins` | 3.138 | 122.705 | **125.843** | 60.878 | 112.384 | 84.051 |
| `prefix_scan` | 3.166 | 113.989 | **117.155** | 62.063 | 102.780 | 81.189 |
| `binary_search` | 3.261 | 112.674 | **115.935** | 62.016 | 94.839 | 79.701 |
| `sort_window` | 3.402 | 114.264 | **117.666** | 62.654 | 108.870 | 84.653 |
| `bloom_filter` | 3.549 | 114.835 | **118.384** | 63.011 | 106.459 | 81.055 |
| `hash_join` | 6.043 | 259.548 | **265.591** | 63.520 | 218.464 | 125.781 |
| `sieve` | 3.156 | 108.047 | **111.203** | 58.046 | 100.887 | 80.743 |
| `fib` | 2.835 | 104.817 | **107.652** | 57.678 | 88.845 | 69.034 |
| `collatz` | 3.035 | 108.717 | **111.752** | 58.675 | 91.888 | 72.273 |
| `matmul` | 3.303 | 106.988 | **110.291** | 58.750 | 104.614 | 91.917 |
| `json_parse` | 54.208 | 444.368 | **498.576** | 113.395 | 163.834 | 182.025 |
| `nbody` | 4.747 | 129.770 | **134.517** | 62.211 | 128.874 | 104.550 |

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
