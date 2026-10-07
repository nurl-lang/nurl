# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-07T18:12:52Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `6aa967be8e9d668a6ef279160b30b85cf8f88dc2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37664565066 |
| NURL | `v0.70.0-33-g6aa967be` |
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
| _(floor: empty program)_ | _1.195_ | _1.136_ | _1.308_ | _17.283_ | _12.795_ |
| `lcg` | 29.770 | **29.741** | 29.785 | 1121.955 | 3038.918 |
| `packet_classifier` | 42.785 | **42.780** | 43.261 | 134.641 | 2711.368 |
| `ring_write` | 29.823 | **29.637** | 29.923 | 52.272 | 3823.814 |
| `histogram_bins` | 29.704 | **29.634** | 30.279 | 51.837 | 3499.637 |
| `prefix_scan` | 17.329 | **16.707** | 16.952 | 49.561 | 2631.984 |
| `binary_search` | 15.226 | **14.995** | 15.597 | 71.266 | 3641.326 |
| `sort_window` | 20.888 | **20.598** | 20.933 | 138.377 | 7140.350 |
| `bloom_filter` | **9.043** | 9.191 | 9.463 | 1661.686 | 4552.627 |
| `hash_join` | **17.013** | 17.808 | 19.003 | 1973.726 | 4708.895 |
| `sieve` | 12.411 | 12.320 | **12.278** | 47.469 | 1831.307 |
| `fib` | 20.315 | **19.920** | 19.974 | 79.162 | 691.251 |
| `collatz` | **9.498** | 9.513 | 9.665 | 38.452 | 422.253 |
| `matmul` | 22.234 | 22.737 | **21.566** | 55.567 | 1841.090 |
| `json_parse` | **4.972** | 5.349 | 6.952 | 26.058 | 25.474 |
| `nbody` | **17.015** | 25.050 | 17.583 | 60.144 | 1518.184 |

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
| _(floor: empty program)_ | _2.985_ | _84.922_ | _**87.907**_ | _50.733_ | _68.665_ | _45.484_ |
| `lcg` | 3.054 | 92.395 | **95.449** | 50.530 | 79.932 | 48.137 |
| `packet_classifier` | 3.956 | 126.918 | **130.874** | 56.102 | 78.450 | 48.629 |
| `ring_write` | 3.210 | 94.833 | **98.043** | 51.037 | 79.388 | 51.302 |
| `histogram_bins` | 3.508 | 99.170 | **102.678** | 52.817 | 90.047 | 55.433 |
| `prefix_scan` | 3.330 | 93.764 | **97.094** | 51.638 | 82.093 | 52.598 |
| `binary_search` | 3.508 | 94.358 | **97.866** | 51.544 | 80.507 | 54.259 |
| `sort_window` | 3.538 | 95.155 | **98.693** | 50.493 | 86.852 | 56.202 |
| `bloom_filter` | 3.898 | 94.903 | **98.801** | 51.047 | 84.102 | 53.348 |
| `hash_join` | 6.018 | 177.909 | **183.927** | 52.695 | 145.103 | 83.676 |
| `sieve` | 3.440 | 93.520 | **96.960** | 50.823 | 84.621 | 56.749 |
| `fib` | 3.283 | 95.006 | **98.289** | 52.581 | 76.248 | 49.130 |
| `collatz` | 3.324 | 95.539 | **98.863** | 51.345 | 78.606 | 49.682 |
| `matmul` | 4.091 | 91.706 | **95.797** | 51.121 | 86.826 | 64.369 |
| `json_parse` | 29.385 | 308.724 | **338.109** | 76.663 | 118.417 | 122.850 |
| `nbody` | 4.695 | 101.939 | **106.634** | 51.356 | 97.771 | 73.162 |

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
