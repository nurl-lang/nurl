# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T04:34:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `d6ca8ba66fa0d269242879d8f2c9890a1f3b29f7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33233969025 |
| NURL | `v0.54.0-9-gd6ca8ba6` |
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
| _(floor: empty program)_ | _1.529_ | _1.505_ | _1.742_ | _23.803_ | _17.668_ |
| `lcg` | **43.945** | 43.973 | 44.205 | 1815.778 | 5280.959 |
| `packet_classifier` | 63.462 | **63.425** | 63.623 | 156.308 | 5325.730 |
| `ring_write` | **47.505** | 47.520 | 47.781 | 73.560 | 6537.876 |
| `histogram_bins` | 44.549 | **44.479** | 44.683 | 74.521 | 6468.347 |
| `prefix_scan` | **24.317** | **24.317** | 24.535 | 71.209 | 4884.785 |
| `binary_search` | 41.304 | **35.610** | 36.443 | 112.641 | 6602.092 |
| `sort_window` | 29.872 | **29.864** | 30.139 | 163.856 | 11240.550 |
| `bloom_filter` | 19.667 | **18.654** | 20.611 | 2759.758 | 7763.025 |
| `hash_join` | **27.633** | 28.572 | 30.025 | 3449.653 | 8363.144 |
| `sieve` | 20.303 | **19.722** | 20.276 | 70.968 | 3756.992 |
| `fib` | **27.765** | 33.112 | 27.994 | 141.601 | 1285.526 |
| `collatz` | 13.637 | **13.558** | 13.772 | 49.836 | 753.466 |
| `matmul` | **45.020** | 45.132 | 45.469 | 82.307 | 3441.502 |
| `json_parse` | **8.609** | 8.786 | 12.123 | 36.904 | 38.426 |
| `nbody` | 26.683 | 44.814 | **26.232** | 94.837 | 3273.030 |

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
| _(floor: empty program)_ | _2.932_ | _99.652_ | _**102.584**_ | _62.994_ | _84.410_ | _63.649_ |
| `lcg` | 3.111 | 110.757 | **113.868** | 63.289 | 94.369 | 72.898 |
| `packet_classifier` | 3.162 | 110.828 | **113.990** | 63.487 | 95.112 | 72.688 |
| `ring_write` | 3.232 | 111.705 | **114.937** | 63.636 | 97.086 | 74.783 |
| `histogram_bins` | 3.391 | 122.561 | **125.952** | 64.145 | 112.915 | 82.308 |
| `prefix_scan` | 3.433 | 113.658 | **117.091** | 64.462 | 102.155 | 77.141 |
| `binary_search` | 3.536 | 113.890 | **117.426** | 64.385 | 97.914 | 80.069 |
| `sort_window` | 3.588 | 114.867 | **118.455** | 63.975 | 107.501 | 85.253 |
| `bloom_filter` | 3.853 | 115.288 | **119.141** | 64.155 | 105.583 | 81.308 |
| `hash_join` | 6.348 | 252.795 | **259.143** | 65.753 | 212.735 | 128.544 |
| `sieve` | 3.407 | 112.465 | **115.872** | 64.434 | 106.537 | 84.772 |
| `fib` | 3.097 | 109.681 | **112.778** | 63.087 | 94.858 | 71.983 |
| `collatz` | 3.312 | 113.036 | **116.348** | 63.600 | 96.895 | 75.069 |
| `matmul` | 3.653 | 114.145 | **117.798** | 64.521 | 110.648 | 97.937 |
| `json_parse` | 53.030 | 416.237 | **469.267** | 114.486 | 161.391 | 183.739 |
| `nbody` | 5.008 | 132.896 | **137.904** | 65.928 | 129.830 | 106.542 |

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
