# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-06T03:57:09Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c417b95cfe0eef7ef63f3918cf7c14827053e064` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37410977898 |
| NURL | `v0.70.0-11-gc417b95c` |
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
| _(floor: empty program)_ | _1.603_ | _1.483_ | _1.691_ | _24.708_ | _18.117_ |
| `lcg` | **39.247** | 39.287 | 39.560 | 1890.985 | 5060.816 |
| `packet_classifier` | 56.637 | **56.482** | 56.628 | 164.909 | 4434.319 |
| `ring_write` | 42.516 | **42.452** | 42.662 | 69.214 | 7010.238 |
| `histogram_bins` | **39.378** | 40.838 | 41.159 | 69.168 | 6273.080 |
| `prefix_scan` | 22.022 | **21.957** | 22.294 | 69.256 | 4524.879 |
| `binary_search` | **36.353** | 38.349 | 40.939 | 108.941 | 6362.626 |
| `sort_window` | **26.769** | 26.774 | 27.116 | 200.318 | 11892.908 |
| `bloom_filter` | **15.633** | 18.165 | 18.732 | 2859.430 | 7559.801 |
| `hash_join` | **27.963** | 28.287 | 29.522 | 3406.361 | 8337.224 |
| `sieve` | 20.959 | **19.674** | 20.494 | 68.963 | 3236.546 |
| `fib` | **29.878** | 30.015 | 30.130 | 134.247 | 1372.904 |
| `collatz` | **12.443** | 12.635 | 12.694 | 53.681 | 744.845 |
| `matmul` | 33.950 | **33.863** | 34.074 | 79.487 | 3202.127 |
| `json_parse` | 8.833 | **8.742** | 11.952 | 38.849 | 42.383 |
| `nbody` | **25.433** | 39.958 | 25.533 | 103.814 | 3122.836 |

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
| _(floor: empty program)_ | _3.528_ | _108.060_ | _**111.588**_ | _63.430_ | _85.540_ | _62.188_ |
| `lcg` | 4.149 | 125.753 | **129.902** | 65.795 | 98.076 | 64.085 |
| `packet_classifier` | 3.889 | 121.138 | **125.027** | 65.608 | 100.411 | 62.501 |
| `ring_write` | 4.334 | 126.487 | **130.821** | 67.600 | 102.810 | 66.143 |
| `histogram_bins` | 4.326 | 128.141 | **132.467** | 67.711 | 120.879 | 72.538 |
| `prefix_scan` | 4.370 | 123.802 | **128.172** | 67.362 | 107.138 | 68.020 |
| `binary_search` | 4.478 | 122.291 | **126.769** | 67.211 | 103.210 | 70.126 |
| `sort_window` | 4.747 | 126.891 | **131.638** | 68.595 | 112.360 | 74.484 |
| `bloom_filter` | 5.412 | 128.103 | **133.515** | 70.056 | 111.585 | 73.271 |
| `hash_join` | 9.475 | 267.656 | **277.131** | 70.228 | 229.061 | 113.949 |
| `sieve` | 4.331 | 117.965 | **122.296** | 65.587 | 109.178 | 72.616 |
| `fib` | 3.871 | 120.254 | **124.125** | 66.091 | 99.193 | 63.137 |
| `collatz` | 4.212 | 118.848 | **123.060** | 64.976 | 100.797 | 66.429 |
| `matmul` | 4.842 | 122.303 | **127.145** | 65.906 | 111.914 | 83.545 |
| `json_parse` | 49.892 | 447.401 | **497.293** | 111.771 | 170.137 | 163.505 |
| `nbody` | 7.156 | 140.041 | **147.197** | 70.874 | 135.767 | 99.764 |

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
