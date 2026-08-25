# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T23:07:57Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ec3614c99dc0d742bbb47861a22b7c138b841c18` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32908998670 |
| NURL | `v0.52.0-12-gec3614c9` |
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
| _(floor: empty program)_ | _1.430_ | _1.406_ | _1.641_ | _23.101_ | _16.848_ |
| `lcg` | 39.093 | **38.881** | 39.102 | 2060.419 | 5122.965 |
| `packet_classifier` | **56.111** | 56.117 | 56.286 | 160.996 | 4270.221 |
| `ring_write` | 42.311 | **42.147** | 42.426 | 66.841 | 6131.342 |
| `histogram_bins` | **39.379** | 40.616 | 39.553 | 64.369 | 6004.909 |
| `prefix_scan` | 21.645 | **21.606** | 21.673 | 64.068 | 4921.709 |
| `binary_search` | **36.035** | 38.102 | 36.999 | 105.240 | 6491.563 |
| `sort_window` | 26.531 | **26.468** | 26.630 | 197.289 | 11296.738 |
| `bloom_filter` | **17.755** | 17.796 | 18.250 | 2858.847 | 7576.252 |
| `hash_join` | **26.799** | 27.840 | 29.310 | 3447.660 | 8486.149 |
| `sieve` | 18.187 | **17.656** | 17.819 | 65.602 | 3256.351 |
| `fib` | **25.039** | 29.594 | 25.206 | 130.705 | 1361.483 |
| `collatz` | 12.188 | **12.064** | 12.391 | 49.523 | 714.241 |
| `matmul` | 34.051 | **33.366** | 33.482 | 75.212 | 3194.287 |
| `json_parse` | 8.930 | **8.460** | 11.552 | 34.673 | 36.880 |
| `nbody` | 25.186 | 39.626 | **24.001** | 101.132 | 3024.068 |

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
| _(floor: empty program)_ | _2.636_ | _92.837_ | _**95.473**_ | _57.736_ | _77.991_ | _54.296_ |
| `lcg` | 2.773 | 93.887 | **96.660** | 57.350 | 89.096 | 61.384 |
| `packet_classifier` | 2.908 | 95.138 | **98.046** | 58.240 | 88.681 | 60.304 |
| `ring_write` | 2.949 | 96.189 | **99.138** | 57.492 | 91.020 | 61.848 |
| `histogram_bins` | 3.042 | 114.833 | **117.875** | 58.823 | 108.363 | 69.878 |
| `prefix_scan` | 3.074 | 98.851 | **101.925** | 57.665 | 95.751 | 66.239 |
| `binary_search` | 3.210 | 101.205 | **104.415** | 58.197 | 93.072 | 66.258 |
| `sort_window` | 3.248 | 105.126 | **108.374** | 58.190 | 102.133 | 72.222 |
| `bloom_filter` | 3.495 | 102.262 | **105.757** | 58.796 | 100.595 | 67.375 |
| `hash_join` | 5.875 | 254.238 | **260.113** | 60.668 | 217.290 | 115.118 |
| `sieve` | 3.058 | 96.861 | **99.919** | 57.804 | 100.044 | 70.278 |
| `fib` | 2.771 | 93.010 | **95.781** | 57.243 | 88.482 | 59.341 |
| `collatz` | 3.009 | 96.214 | **99.223** | 57.474 | 89.350 | 62.411 |
| `matmul` | 3.360 | 98.792 | **102.152** | 58.206 | 104.041 | 82.691 |
| `json_parse` | 52.733 | 428.586 | **481.319** | 108.343 | 157.946 | 163.596 |
| `nbody` | 4.622 | 122.730 | **127.352** | 59.031 | 125.041 | 93.146 |

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
