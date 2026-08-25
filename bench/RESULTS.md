# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T22:13:56Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d4d9ba8f29d70cfa721ca563cddfc53c34b43e1d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32904730115 |
| NURL | `v0.52.0-6-gd4d9ba8f` |
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
| _(floor: empty program)_ | _1.549_ | _1.549_ | _1.754_ | _23.976_ | _18.388_ |
| `lcg` | **44.087** | 44.095 | 44.177 | 1823.535 | 5324.627 |
| `packet_classifier` | 63.461 | **63.413** | 63.728 | 157.872 | 4879.284 |
| `ring_write` | **47.507** | 47.552 | 47.841 | 74.174 | 6544.390 |
| `histogram_bins` | 44.579 | **44.563** | 44.813 | 75.543 | 6266.465 |
| `prefix_scan` | **24.370** | 24.380 | 24.681 | 72.329 | 4983.795 |
| `binary_search` | **33.485** | 35.544 | 36.539 | 111.537 | 6777.892 |
| `sort_window` | **29.888** | 29.999 | 30.070 | 169.183 | 11051.295 |
| `bloom_filter` | 19.710 | **18.664** | 20.603 | 2743.203 | 7703.283 |
| `hash_join` | **27.532** | 28.595 | 29.999 | 3446.846 | 8252.250 |
| `sieve` | 20.389 | **20.064** | 20.366 | 71.322 | 3491.640 |
| `fib` | **27.929** | 33.173 | 28.091 | 142.511 | 1287.167 |
| `collatz` | 13.696 | **13.602** | 13.913 | 53.741 | 753.460 |
| `matmul` | 46.400 | 46.686 | **45.773** | 84.495 | 3649.351 |
| `json_parse` | **8.655** | 8.767 | 12.092 | 39.472 | 38.364 |
| `nbody` | 26.713 | 44.867 | **26.163** | 95.081 | 3219.291 |

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
| _(floor: empty program)_ | _2.989_ | _101.908_ | _**104.897**_ | _64.083_ | _86.812_ | _58.333_ |
| `lcg` | 3.229 | 104.695 | **107.924** | 64.952 | 97.897 | 66.578 |
| `packet_classifier` | 3.182 | 102.886 | **106.068** | 63.644 | 97.766 | 64.554 |
| `ring_write` | 3.344 | 105.185 | **108.529** | 65.544 | 101.980 | 66.430 |
| `histogram_bins` | 3.433 | 127.963 | **131.396** | 66.072 | 116.949 | 74.226 |
| `prefix_scan` | 3.463 | 107.226 | **110.689** | 65.084 | 107.309 | 71.165 |
| `binary_search` | 3.575 | 111.239 | **114.814** | 65.265 | 100.773 | 72.919 |
| `sort_window` | 3.693 | 115.765 | **119.458** | 65.605 | 111.220 | 76.224 |
| `bloom_filter` | 3.869 | 110.678 | **114.547** | 65.386 | 108.175 | 72.863 |
| `hash_join` | 6.320 | 252.428 | **258.748** | 67.153 | 219.253 | 120.285 |
| `sieve` | 3.455 | 107.460 | **110.915** | 64.813 | 109.381 | 75.783 |
| `fib` | 3.129 | 104.682 | **107.811** | 65.022 | 97.505 | 64.207 |
| `collatz` | 3.334 | 108.137 | **111.471** | 64.788 | 99.682 | 67.292 |
| `matmul` | 3.731 | 109.869 | **113.600** | 65.354 | 114.038 | 89.548 |
| `json_parse` | 51.241 | 422.018 | **473.259** | 115.332 | 167.401 | 175.531 |
| `nbody` | 5.078 | 134.083 | **139.161** | 66.714 | 132.362 | 98.473 |

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
