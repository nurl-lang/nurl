# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-30T17:14:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `8379113f61f90dc16bd94672ac4ecc6e958a2261` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36749467437 |
| NURL | `v0.68.0` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
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
| _(floor: empty program)_ | _1.258_ | _1.262_ | _1.462_ | _23.294_ | _15.690_ |
| `lcg` | 41.029 | **40.725** | 40.789 | 1631.267 | 4253.546 |
| `packet_classifier` | 70.491 | 70.174 | **69.886** | 172.818 | 3447.388 |
| `ring_write` | 46.571 | **46.446** | 47.267 | 71.881 | 5269.669 |
| `histogram_bins` | 41.881 | **41.797** | 41.957 | 68.834 | 5013.719 |
| `prefix_scan` | 22.462 | **22.273** | 22.753 | 67.694 | 3613.217 |
| `binary_search` | 39.947 | 31.886 | **30.894** | 113.962 | 5285.131 |
| `sort_window` | 39.948 | **39.884** | 41.003 | 182.089 | 9126.475 |
| `bloom_filter` | **14.215** | 14.398 | 14.560 | 2460.230 | 6536.753 |
| `hash_join` | **23.983** | 25.544 | 25.731 | 3067.863 | 7308.200 |
| `sieve` | 36.851 | 36.459 | **36.447** | 84.077 | 2972.548 |
| `fib` | 28.790 | 30.899 | **28.473** | 114.402 | 913.240 |
| `collatz` | **14.939** | 15.233 | 16.147 | 59.314 | 579.911 |
| `matmul` | 20.519 | **19.880** | 20.481 | 72.903 | 2730.541 |
| `json_parse` | 7.475 | **7.423** | 9.534 | 31.868 | 32.914 |
| `nbody` | **22.384** | 31.707 | 22.611 | 81.846 | 2140.991 |

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
| _(floor: empty program)_ | _3.265_ | _83.976_ | _**87.241**_ | _52.271_ | _65.410_ | _58.217_ |
| `lcg` | 3.365 | 93.540 | **96.905** | 52.088 | 72.635 | 67.018 |
| `packet_classifier` | 3.585 | 99.701 | **103.286** | 54.744 | 78.344 | 66.900 |
| `ring_write` | 3.762 | 101.054 | **104.816** | 54.630 | 80.716 | 69.064 |
| `histogram_bins` | 4.364 | 118.499 | **122.863** | 60.918 | 105.860 | 84.286 |
| `prefix_scan` | 3.865 | 97.709 | **101.574** | 53.453 | 81.405 | 68.951 |
| `binary_search` | 4.009 | 98.991 | **103.000** | 53.271 | 74.722 | 70.854 |
| `sort_window` | 4.065 | 97.946 | **102.011** | 51.660 | 86.576 | 76.707 |
| `bloom_filter` | 4.755 | 96.950 | **101.705** | 52.249 | 83.562 | 70.779 |
| `hash_join` | 8.658 | 223.548 | **232.206** | 57.747 | 182.616 | 119.969 |
| `sieve` | 3.847 | 93.702 | **97.549** | 52.372 | 84.172 | 76.312 |
| `fib` | 3.388 | 94.291 | **97.679** | 51.036 | 74.007 | 64.354 |
| `collatz` | 3.665 | 97.645 | **101.310** | 53.154 | 76.219 | 68.325 |
| `matmul` | 4.199 | 95.436 | **99.635** | 52.213 | 86.441 | 91.738 |
| `json_parse` | 98.684 | 396.555 | **495.239** | 148.160 | 135.206 | 180.095 |
| `nbody` | 6.128 | 112.967 | **119.095** | 55.037 | 105.581 | 99.392 |

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
