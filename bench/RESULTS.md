# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-03T20:30:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1ada16f1a626dd9bba7ea1d4e4d3f43610934098` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37151481383 |
| NURL | `v0.69.1-3-g1ada16f1` |
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
| _(floor: empty program)_ | _1.450_ | _1.443_ | _1.659_ | _23.187_ | _18.022_ |
| `lcg` | **39.144** | 39.239 | 39.535 | 1934.250 | 5093.030 |
| `packet_classifier` | 56.437 | **56.281** | 56.475 | 162.617 | 4501.182 |
| `ring_write` | 42.243 | **42.228** | 42.563 | 66.587 | 6447.392 |
| `histogram_bins` | **39.435** | 40.634 | 40.874 | 68.067 | 6150.968 |
| `prefix_scan` | 21.758 | **21.622** | 21.876 | 64.801 | 4947.873 |
| `binary_search` | 39.621 | **38.045** | 40.752 | 105.796 | 7094.483 |
| `sort_window` | **26.537** | 26.599 | 26.620 | 197.916 | 11656.117 |
| `bloom_filter` | **16.498** | 17.816 | 18.236 | 2820.215 | 7498.364 |
| `hash_join` | **26.983** | 27.906 | 29.339 | 3407.860 | 8374.580 |
| `sieve` | 18.323 | **18.040** | 18.176 | 66.745 | 3519.430 |
| `fib` | **25.132** | 29.858 | 29.988 | 132.389 | 1374.360 |
| `collatz` | 12.256 | **12.125** | 12.384 | 50.030 | 742.497 |
| `matmul` | 33.334 | **33.329** | 33.603 | 76.294 | 3209.188 |
| `json_parse` | 8.885 | **8.609** | 11.924 | 35.095 | 38.753 |
| `nbody` | **25.159** | 39.662 | 25.217 | 100.729 | 3158.284 |

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
| _(floor: empty program)_ | _3.523_ | _102.550_ | _**106.073**_ | _62.936_ | _83.080_ | _53.632_ |
| `lcg` | 3.543 | 113.439 | **116.982** | 62.969 | 93.591 | 59.146 |
| `packet_classifier` | 3.714 | 113.245 | **116.959** | 62.506 | 94.159 | 58.995 |
| `ring_write` | 3.917 | 111.193 | **115.110** | 61.554 | 92.001 | 59.386 |
| `histogram_bins` | 4.067 | 120.706 | **124.773** | 61.557 | 109.416 | 66.409 |
| `prefix_scan` | 4.047 | 112.418 | **116.465** | 61.418 | 97.453 | 62.612 |
| `binary_search` | 4.148 | 108.929 | **113.077** | 59.753 | 90.757 | 63.038 |
| `sort_window` | 4.326 | 113.648 | **117.974** | 60.906 | 103.527 | 68.486 |
| `bloom_filter` | 4.936 | 113.279 | **118.215** | 59.839 | 99.743 | 63.964 |
| `hash_join` | 9.296 | 262.162 | **271.458** | 66.924 | 221.979 | 110.090 |
| `sieve` | 4.155 | 113.764 | **117.919** | 62.556 | 105.432 | 68.449 |
| `fib` | 3.608 | 111.644 | **115.252** | 61.515 | 91.041 | 57.047 |
| `collatz` | 3.863 | 110.507 | **114.370** | 60.546 | 93.007 | 59.138 |
| `matmul` | 4.494 | 112.295 | **116.789** | 62.376 | 105.911 | 78.298 |
| `json_parse` | 104.538 | 458.842 | **563.380** | 162.533 | 162.366 | 155.823 |
| `nbody` | 6.586 | 128.393 | **134.979** | 63.485 | 129.009 | 94.580 |

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
