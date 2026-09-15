# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-15T05:22:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `67fa20a87bd13c7eeb548e37762cb590a9f638f6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34932174333 |
| NURL | `v0.65.0-24-g67fa20a8` |
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
| _(floor: empty program)_ | _1.555_ | _1.574_ | _1.765_ | _24.534_ | _17.923_ |
| `lcg` | 44.077 | **44.063** | 44.328 | 1841.613 | 5298.205 |
| `packet_classifier` | **63.525** | 63.526 | 63.838 | 158.038 | 4587.439 |
| `ring_write` | **47.835** | 47.856 | 48.001 | 74.626 | 6631.344 |
| `histogram_bins` | **44.643** | 44.677 | 44.891 | 74.865 | 6222.908 |
| `prefix_scan` | 24.388 | **24.378** | 24.612 | 71.707 | 4692.973 |
| `binary_search` | 41.406 | **35.719** | 36.702 | 111.578 | 6921.832 |
| `sort_window` | 29.979 | **29.932** | 30.321 | 164.988 | 11468.402 |
| `bloom_filter` | **17.292** | 18.726 | 20.611 | 2766.082 | 7852.715 |
| `hash_join` | **27.570** | 28.542 | 29.976 | 3463.774 | 8338.634 |
| `sieve` | 20.657 | **20.049** | 20.665 | 74.764 | 3535.215 |
| `fib` | **27.988** | 33.328 | 28.061 | 142.666 | 1283.305 |
| `collatz` | 13.621 | **13.607** | 13.862 | 52.630 | 755.721 |
| `matmul` | 45.715 | **45.481** | 47.201 | 84.954 | 3524.613 |
| `json_parse` | 9.453 | **8.867** | 12.103 | 38.193 | 40.358 |
| `nbody` | 26.870 | 44.952 | **26.319** | 97.575 | 3376.554 |

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
| _(floor: empty program)_ | _3.721_ | _106.763_ | _**110.484**_ | _66.755_ | _87.751_ | _66.312_ |
| `lcg` | 3.908 | 115.853 | **119.761** | 66.786 | 98.369 | 74.569 |
| `packet_classifier` | 3.971 | 117.501 | **121.472** | 66.483 | 105.608 | 75.888 |
| `ring_write` | 4.189 | 124.283 | **128.472** | 68.998 | 104.779 | 77.781 |
| `histogram_bins` | 4.316 | 126.697 | **131.013** | 70.341 | 117.355 | 83.344 |
| `prefix_scan` | 4.339 | 119.616 | **123.955** | 66.348 | 105.896 | 79.998 |
| `binary_search` | 4.823 | 125.431 | **130.254** | 70.112 | 103.464 | 80.783 |
| `sort_window` | 4.732 | 123.517 | **128.249** | 67.896 | 112.006 | 88.909 |
| `bloom_filter` | 5.355 | 139.753 | **145.108** | 74.475 | 126.489 | 82.215 |
| `hash_join` | 9.673 | 256.035 | **265.708** | 71.870 | 215.217 | 132.068 |
| `sieve` | 4.391 | 116.557 | **120.948** | 66.582 | 109.349 | 85.449 |
| `fib` | 3.868 | 116.121 | **119.989** | 68.154 | 101.726 | 73.723 |
| `collatz` | 4.356 | 118.728 | **123.084** | 66.292 | 99.061 | 77.388 |
| `matmul` | 4.947 | 121.627 | **126.574** | 69.658 | 114.939 | 99.411 |
| `json_parse` | 102.983 | 455.913 | **558.896** | 166.499 | 164.834 | 187.007 |
| `nbody` | 6.975 | 140.760 | **147.735** | 71.520 | 134.975 | 107.951 |

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
