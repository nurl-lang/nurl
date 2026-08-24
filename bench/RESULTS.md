# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-24T13:14:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3523ed93edca645d6022f4563d2ea59b618f8810` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32731016526 |
| NURL | `v0.50.0-12-g3523ed93` |
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
| _(floor: empty program)_ | _1.546_ | _1.541_ | _1.769_ | _25.672_ | _17.819_ |
| `lcg` | **43.994** | 44.034 | 44.208 | 1815.324 | 5337.711 |
| `packet_classifier` | 63.498 | **63.404** | 63.647 | 158.388 | 4794.660 |
| `ring_write` | **47.514** | 47.576 | 47.810 | 71.375 | 6674.567 |
| `histogram_bins` | 44.576 | **44.507** | 44.775 | 74.068 | 6080.686 |
| `prefix_scan` | **24.365** | 24.379 | 24.586 | 70.816 | 5114.415 |
| `binary_search` | **33.238** | 35.573 | 36.538 | 111.486 | 6727.514 |
| `sort_window` | 29.906 | **29.878** | 30.103 | 165.509 | 11548.409 |
| `bloom_filter` | 19.653 | **18.647** | 20.566 | 2723.747 | 7650.932 |
| `hash_join` | **27.524** | 28.618 | 30.170 | 3402.904 | 8386.782 |
| `sieve` | 20.251 | **20.094** | 20.441 | 71.261 | 3492.550 |
| `fib` | **27.807** | 33.056 | 28.077 | 142.855 | 1287.992 |
| `collatz` | 13.659 | **13.644** | 13.874 | 51.908 | 758.144 |
| `matmul` | **45.407** | 46.336 | 45.914 | 84.035 | 3496.311 |
| `json_parse` | **8.707** | 8.716 | 12.087 | 36.332 | 38.181 |
| `nbody` | 26.742 | 44.957 | **26.218** | 95.884 | 3236.309 |

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
| _(floor: empty program)_ | _2.943_ | _100.981_ | _**103.924**_ | _63.880_ | _84.350_ | _58.717_ |
| `lcg` | 3.121 | 101.595 | **104.716** | 63.480 | 94.297 | 64.227 |
| `packet_classifier` | 3.203 | 101.342 | **104.545** | 64.134 | 96.355 | 63.560 |
| `ring_write` | 3.287 | 103.521 | **106.808** | 64.065 | 98.240 | 65.055 |
| `histogram_bins` | 3.403 | 122.004 | **125.407** | 64.461 | 113.762 | 72.542 |
| `prefix_scan` | 3.422 | 105.609 | **109.031** | 64.776 | 101.767 | 68.598 |
| `binary_search` | 3.549 | 110.860 | **114.409** | 65.732 | 101.804 | 70.639 |
| `sort_window` | 3.588 | 113.185 | **116.773** | 63.802 | 109.161 | 75.316 |
| `bloom_filter` | 3.834 | 110.480 | **114.314** | 64.199 | 106.750 | 71.070 |
| `hash_join` | 6.537 | 256.681 | **263.218** | 69.181 | 216.491 | 120.682 |
| `sieve` | 3.466 | 106.524 | **109.990** | 64.585 | 108.651 | 74.469 |
| `fib` | 3.114 | 102.167 | **105.281** | 63.241 | 96.124 | 63.154 |
| `collatz` | 3.364 | 107.050 | **110.414** | 65.119 | 99.376 | 67.193 |
| `matmul` | 3.691 | 109.540 | **113.231** | 65.585 | 111.979 | 88.158 |
| `json_parse` | 52.203 | 416.547 | **468.750** | 114.514 | 163.932 | 171.616 |
| `nbody` | 5.011 | 135.141 | **140.152** | 67.242 | 133.226 | 97.645 |

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
