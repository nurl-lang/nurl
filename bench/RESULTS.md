# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-08T11:51:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372432 KiB |
| Commit | `868b61e65c525fb99f81b48c24fd0a999a26d540` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34222518458 |
| NURL | `v0.61.1-6-g868b61e6` |
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
| _(floor: empty program)_ | _1.101_ | _1.078_ | _1.239_ | _20.582_ | _14.113_ |
| `lcg` | **35.281** | 35.751 | 35.331 | 1408.563 | 3887.281 |
| `packet_classifier` | 61.424 | 62.366 | **61.249** | 150.823 | 3126.378 |
| `ring_write` | 39.039 | **38.783** | 39.526 | 59.716 | 4582.971 |
| `histogram_bins` | **36.076** | 36.607 | 36.435 | 63.424 | 4438.412 |
| `prefix_scan` | 19.595 | **19.550** | 19.727 | 58.162 | 3170.140 |
| `binary_search` | 34.684 | 27.623 | **27.321** | 101.211 | 5169.423 |
| `sort_window` | **34.775** | 34.932 | 35.754 | 160.024 | 8524.568 |
| `bloom_filter` | **12.459** | 12.580 | 12.845 | 2135.538 | 5777.086 |
| `hash_join` | **20.809** | 22.090 | 22.166 | 2658.369 | 6224.880 |
| `sieve` | 31.714 | **31.465** | 33.072 | 75.674 | 2363.667 |
| `fib` | **25.041** | 26.537 | 25.082 | 97.373 | 793.607 |
| `collatz` | **13.432** | 13.610 | 14.011 | 52.528 | 501.566 |
| `matmul` | 17.673 | **17.468** | 18.133 | 65.757 | 2176.615 |
| `json_parse` | 6.733 | **6.522** | 8.270 | 27.753 | 29.044 |
| `nbody` | **19.479** | 27.436 | 19.627 | 71.007 | 1938.122 |

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
| _(floor: empty program)_ | _2.154_ | _70.631_ | _**72.785**_ | _42.786_ | _58.954_ | _45.342_ |
| `lcg` | 2.302 | 82.977 | **85.279** | 45.404 | 71.475 | 51.292 |
| `packet_classifier` | 2.351 | 79.488 | **81.839** | 43.127 | 67.478 | 52.735 |
| `ring_write` | 2.468 | 82.601 | **85.069** | 44.539 | 65.843 | 52.519 |
| `histogram_bins` | 2.528 | 87.430 | **89.958** | 42.374 | 78.338 | 58.213 |
| `prefix_scan` | 2.558 | 85.395 | **87.953** | 43.125 | 69.410 | 56.047 |
| `binary_search` | 2.672 | 83.551 | **86.223** | 44.310 | 68.499 | 58.253 |
| `sort_window` | 2.768 | 89.331 | **92.099** | 47.532 | 74.555 | 62.534 |
| `bloom_filter` | 2.954 | 84.650 | **87.604** | 43.982 | 71.182 | 55.755 |
| `hash_join` | 5.005 | 194.400 | **199.405** | 49.053 | 157.070 | 98.344 |
| `sieve` | 2.599 | 81.380 | **83.979** | 43.664 | 69.933 | 60.896 |
| `fib` | 2.374 | 79.734 | **82.108** | 43.411 | 62.227 | 49.531 |
| `collatz` | 2.512 | 83.133 | **85.645** | 44.695 | 66.688 | 52.371 |
| `matmul` | 2.756 | 80.751 | **83.507** | 43.262 | 73.423 | 72.175 |
| `json_parse` | 48.447 | 350.284 | **398.731** | 93.206 | 119.525 | 150.619 |
| `nbody` | 3.768 | 95.639 | **99.407** | 45.311 | 91.587 | 81.365 |

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
