# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-07T15:13:23Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e5e4e0f2f93cf14a5afcf2cf0ada4361e3ae8f29` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34136737404 |
| NURL | `v0.61.1` |
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
| _(floor: empty program)_ | _1.533_ | _1.569_ | _1.777_ | _27.967_ | _18.428_ |
| `lcg` | **44.057** | 44.092 | 44.205 | 1823.383 | 5337.008 |
| `packet_classifier` | **63.399** | 63.484 | 63.768 | 159.500 | 4732.802 |
| `ring_write` | **47.524** | 47.525 | 47.730 | 73.428 | 6683.777 |
| `histogram_bins` | 44.587 | **44.568** | 44.805 | 76.068 | 6224.934 |
| `prefix_scan` | 24.401 | **24.281** | 24.572 | 71.987 | 4758.659 |
| `binary_search` | 41.304 | **35.624** | 36.550 | 114.179 | 6789.362 |
| `sort_window` | 29.963 | **29.903** | 30.183 | 165.728 | 12227.347 |
| `bloom_filter` | 19.660 | **18.626** | 20.551 | 2761.459 | 7966.710 |
| `hash_join` | **27.569** | 28.613 | 30.003 | 3409.923 | 8342.125 |
| `sieve` | 20.607 | **19.946** | 20.271 | 71.438 | 3570.784 |
| `fib` | **27.813** | 33.111 | 28.155 | 142.547 | 1279.800 |
| `collatz` | 13.727 | **13.630** | 13.930 | 53.954 | 747.177 |
| `matmul` | **45.820** | 45.825 | 45.944 | 83.045 | 3432.802 |
| `json_parse` | 9.026 | **8.897** | 12.097 | 39.475 | 41.421 |
| `nbody` | 26.874 | 45.051 | **26.429** | 96.981 | 3361.149 |

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
| _(floor: empty program)_ | _3.013_ | _105.718_ | _**108.731**_ | _65.998_ | _89.666_ | _58.587_ |
| `lcg` | 3.148 | 116.884 | **120.032** | 66.280 | 100.089 | 64.299 |
| `packet_classifier` | 3.212 | 116.822 | **120.034** | 65.775 | 99.633 | 65.030 |
| `ring_write` | 3.365 | 118.684 | **122.049** | 65.815 | 100.551 | 64.545 |
| `histogram_bins` | 3.392 | 126.261 | **129.653** | 66.111 | 116.624 | 72.644 |
| `prefix_scan` | 3.447 | 118.183 | **121.630** | 65.737 | 105.895 | 68.453 |
| `binary_search` | 3.639 | 117.423 | **121.062** | 66.487 | 101.633 | 69.846 |
| `sort_window` | 3.687 | 122.743 | **126.430** | 67.529 | 111.173 | 74.427 |
| `bloom_filter` | 3.891 | 122.688 | **126.579** | 66.949 | 108.901 | 70.663 |
| `hash_join` | 6.511 | 258.567 | **265.078** | 69.245 | 218.105 | 119.027 |
| `sieve` | 3.453 | 119.356 | **122.809** | 67.527 | 112.870 | 75.169 |
| `fib` | 3.148 | 117.860 | **121.008** | 66.958 | 99.110 | 63.460 |
| `collatz` | 3.335 | 122.292 | **125.627** | 68.129 | 103.002 | 67.651 |
| `matmul` | 3.731 | 120.624 | **124.355** | 67.668 | 114.281 | 88.128 |
| `json_parse` | 57.245 | 445.940 | **503.185** | 124.285 | 167.810 | 176.106 |
| `nbody` | 5.145 | 141.723 | **146.868** | 70.307 | 137.169 | 98.560 |

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
