# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-01T03:17:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `62c54157fcb302c2aec3bfbc008039f36d38834b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33465390902 |
| NURL | `v0.57.0-6-g62c54157` |
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
| _(floor: empty program)_ | _1.524_ | _1.564_ | _1.773_ | _25.439_ | _17.825_ |
| `lcg` | **43.988** | 44.101 | 44.265 | 1847.255 | 5512.200 |
| `packet_classifier` | 63.401 | **63.386** | 63.698 | 160.352 | 4538.686 |
| `ring_write` | **47.503** | 47.574 | 47.844 | 73.442 | 7521.844 |
| `histogram_bins` | **44.529** | 44.533 | 44.733 | 74.159 | 6449.335 |
| `prefix_scan` | **24.377** | 24.379 | 24.663 | 71.169 | 4757.764 |
| `binary_search` | 41.349 | **35.627** | 36.554 | 113.003 | 6498.513 |
| `sort_window` | 29.977 | **29.866** | 30.157 | 165.751 | 12275.122 |
| `bloom_filter` | 19.654 | **18.675** | 20.611 | 2719.983 | 8182.462 |
| `hash_join` | **27.584** | 28.550 | 30.092 | 3426.512 | 8182.837 |
| `sieve` | 20.113 | **19.991** | 20.308 | 71.062 | 3494.101 |
| `fib` | **27.847** | 33.128 | 28.024 | 142.967 | 1286.624 |
| `collatz` | 13.673 | **13.601** | 13.872 | 51.349 | 753.715 |
| `matmul` | **44.908** | 45.829 | 46.577 | 82.834 | 3609.213 |
| `json_parse` | **8.577** | 8.773 | 12.049 | 37.182 | 37.624 |
| `nbody` | 26.725 | 44.911 | **26.279** | 95.850 | 3206.427 |

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
| _(floor: empty program)_ | _2.904_ | _100.572_ | _**103.476**_ | _62.912_ | _84.660_ | _65.379_ |
| `lcg` | 3.083 | 110.574 | **113.657** | 62.863 | 94.563 | 73.268 |
| `packet_classifier` | 3.224 | 112.200 | **115.424** | 63.052 | 96.276 | 74.324 |
| `ring_write` | 3.307 | 111.838 | **115.145** | 63.310 | 98.429 | 74.571 |
| `histogram_bins` | 3.384 | 121.554 | **124.938** | 63.600 | 113.362 | 83.600 |
| `prefix_scan` | 3.421 | 113.155 | **116.576** | 63.488 | 101.784 | 79.227 |
| `binary_search` | 3.609 | 114.212 | **117.821** | 64.107 | 98.883 | 80.241 |
| `sort_window` | 3.667 | 117.390 | **121.057** | 64.247 | 107.311 | 85.136 |
| `bloom_filter` | 3.864 | 116.029 | **119.893** | 64.583 | 107.003 | 81.456 |
| `hash_join` | 6.430 | 252.062 | **258.492** | 66.137 | 213.262 | 130.960 |
| `sieve` | 3.448 | 114.873 | **118.321** | 63.695 | 107.985 | 87.671 |
| `fib` | 3.192 | 110.378 | **113.570** | 63.408 | 94.676 | 72.412 |
| `collatz` | 3.318 | 113.317 | **116.635** | 63.453 | 96.398 | 76.878 |
| `matmul` | 3.652 | 113.627 | **117.279** | 63.918 | 109.306 | 97.802 |
| `json_parse` | 54.287 | 416.345 | **470.632** | 116.084 | 160.893 | 182.874 |
| `nbody` | 5.022 | 132.100 | **137.122** | 65.227 | 130.066 | 107.551 |

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
