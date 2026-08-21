# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-21T14:22:59Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `a9fbe4fb4aa5e788ede04e783a8adf54897e7996` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32491410194 |
| NURL | `v0.48.0` |
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
| _(floor: empty program)_ | _1.531_ | _1.559_ | _1.756_ | _28.030_ | _17.903_ |
| `lcg` | 43.997 | **43.996** | 44.225 | 1820.202 | 5315.558 |
| `packet_classifier` | **63.428** | 63.445 | 63.646 | 156.727 | 4712.005 |
| `ring_write` | 47.503 | **47.484** | 47.802 | 73.294 | 6567.864 |
| `histogram_bins` | 44.550 | **44.485** | 44.781 | 74.242 | 6443.314 |
| `prefix_scan` | **24.349** | 24.388 | 24.602 | 71.216 | 4626.368 |
| `binary_search` | **34.030** | 35.630 | 36.535 | 112.272 | 7168.321 |
| `sort_window` | 29.898 | **29.837** | 30.164 | 165.368 | 11562.666 |
| `bloom_filter` | 19.675 | **18.668** | 20.543 | 2737.664 | 7744.411 |
| `hash_join` | **27.646** | 28.625 | 30.108 | 3475.814 | 8222.253 |
| `sieve` | 20.400 | **20.037** | 20.152 | 72.073 | 3370.976 |
| `fib` | **27.844** | 33.099 | 28.026 | 142.846 | 1290.928 |
| `collatz` | 13.645 | **13.598** | 13.849 | 51.598 | 751.186 |
| `matmul` | **44.744** | 46.086 | 45.517 | 84.766 | 3317.774 |
| `json_parse` | **8.717** | 8.822 | 12.139 | 38.475 | 38.714 |
| `nbody` | 26.739 | 44.857 | **26.383** | 96.321 | 3258.089 |

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
| _(floor: empty program)_ | _2.861_ | _98.348_ | _**101.209**_ | _62.968_ | _83.213_ | _57.768_ |
| `lcg` | 3.106 | 104.336 | **107.442** | 63.799 | 94.527 | 63.682 |
| `packet_classifier` | 3.142 | 100.335 | **103.477** | 62.319 | 95.736 | 64.050 |
| `ring_write` | 3.315 | 102.660 | **105.975** | 63.703 | 97.469 | 64.887 |
| `histogram_bins` | 3.339 | 121.212 | **124.551** | 63.428 | 113.584 | 73.218 |
| `prefix_scan` | 3.575 | 106.091 | **109.666** | 64.118 | 102.426 | 68.789 |
| `binary_search` | 3.542 | 108.728 | **112.270** | 63.556 | 98.085 | 70.419 |
| `sort_window` | 3.614 | 111.171 | **114.785** | 63.262 | 107.313 | 74.764 |
| `bloom_filter` | 3.891 | 109.921 | **113.812** | 64.806 | 108.012 | 70.867 |
| `hash_join` | 6.517 | 252.048 | **258.565** | 66.769 | 213.519 | 119.474 |
| `sieve` | 3.467 | 106.348 | **109.815** | 64.795 | 108.893 | 75.024 |
| `fib` | 3.165 | 103.896 | **107.061** | 64.390 | 98.043 | 63.351 |
| `collatz` | 3.289 | 105.822 | **109.111** | 64.501 | 98.082 | 66.285 |
| `matmul` | 3.752 | 108.627 | **112.379** | 65.138 | 110.869 | 88.571 |
| `json_parse` | 52.941 | 418.206 | **471.147** | 116.856 | 163.651 | 172.186 |
| `nbody` | 5.067 | 132.685 | **137.752** | 66.178 | 131.888 | 97.501 |

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
