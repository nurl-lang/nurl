# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T07:30:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `8f5be072bc63daae10ef65201154fa9dfc94ddf6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33240843433 |
| NURL | `v0.54.0-16-g8f5be072` |
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
| _(floor: empty program)_ | _1.142_ | _1.130_ | _1.259_ | _17.429_ | _11.786_ |
| `lcg` | 30.277 | **30.112** | 30.243 | 1069.900 | 3258.481 |
| `packet_classifier` | **52.742** | 52.991 | 53.340 | 131.769 | 2628.167 |
| `ring_write` | **33.062** | 33.232 | 34.384 | 55.629 | 3763.399 |
| `histogram_bins` | 31.214 | **31.148** | 31.302 | 52.191 | 3661.214 |
| `prefix_scan` | 16.764 | **16.606** | 16.979 | 50.671 | 2668.925 |
| `binary_search` | 27.477 | 22.524 | **20.649** | 86.043 | 4017.091 |
| `sort_window` | 33.205 | **32.773** | 35.418 | 137.016 | 6938.474 |
| `bloom_filter` | 10.986 | **10.736** | 10.942 | 1851.247 | 5135.684 |
| `hash_join` | **18.239** | 19.432 | 19.457 | 2394.636 | 5229.485 |
| `sieve` | 32.881 | **32.541** | 32.885 | 69.693 | 2015.605 |
| `fib` | **17.850** | 20.920 | 17.952 | 84.890 | 672.018 |
| `collatz` | **11.301** | 11.605 | 12.284 | 46.829 | 422.064 |
| `matmul` | 15.717 | **14.971** | 15.329 | 56.716 | 1892.537 |
| `json_parse` | **5.652** | 5.937 | 7.105 | 24.507 | 24.635 |
| `nbody` | **16.339** | 22.891 | 16.391 | 65.430 | 1585.223 |

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
| _(floor: empty program)_ | _2.128_ | _71.924_ | _**74.052**_ | _45.143_ | _59.157_ | _51.995_ |
| `lcg` | 2.243 | 77.700 | **79.943** | 44.540 | 65.854 | 58.297 |
| `packet_classifier` | 2.391 | 79.865 | **82.256** | 45.220 | 66.972 | 58.883 |
| `ring_write` | 2.500 | 79.576 | **82.076** | 45.617 | 65.179 | 59.253 |
| `histogram_bins` | 2.430 | 83.138 | **85.568** | 44.606 | 73.432 | 61.827 |
| `prefix_scan` | 2.401 | 74.438 | **76.839** | 41.849 | 64.783 | 59.212 |
| `binary_search` | 2.478 | 76.016 | **78.494** | 40.746 | 61.953 | 59.761 |
| `sort_window` | 2.501 | 76.612 | **79.113** | 43.395 | 70.774 | 66.210 |
| `bloom_filter` | 2.724 | 77.067 | **79.791** | 42.967 | 70.104 | 61.286 |
| `hash_join` | 4.440 | 170.512 | **174.952** | 46.903 | 145.888 | 99.580 |
| `sieve` | 2.417 | 77.835 | **80.252** | 43.526 | 73.949 | 67.743 |
| `fib` | 2.375 | 82.525 | **84.900** | 46.501 | 66.572 | 57.135 |
| `collatz` | 2.402 | 78.939 | **81.341** | 43.901 | 65.378 | 59.383 |
| `matmul` | 2.632 | 79.212 | **81.844** | 44.911 | 75.292 | 76.765 |
| `json_parse` | 38.790 | 307.779 | **346.569** | 84.104 | 119.101 | 144.870 |
| `nbody` | 3.329 | 92.029 | **95.358** | 47.919 | 85.523 | 81.858 |

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
