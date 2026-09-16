# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-16T03:27:23Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1b72a44c0f46e575611c3fb26534342478dccba8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/35051613452 |
| NURL | `v0.65.0-28-g1b72a44c` |
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
| _(floor: empty program)_ | _1.134_ | _1.109_ | _1.401_ | _18.589_ | _13.846_ |
| `lcg` | 35.066 | **35.035** | 35.117 | 1373.034 | 3772.075 |
| `packet_classifier` | 59.227 | **59.126** | 59.532 | 148.278 | 3173.815 |
| `ring_write` | 38.773 | **38.357** | 38.961 | 58.881 | 4634.691 |
| `histogram_bins` | 36.061 | **35.941** | 36.073 | 58.346 | 4286.452 |
| `prefix_scan` | **19.167** | 19.235 | 19.761 | 57.418 | 3232.553 |
| `binary_search` | 34.090 | 27.694 | **26.287** | 98.126 | 4860.908 |
| `sort_window` | 34.291 | **34.281** | 35.135 | 158.961 | 8292.588 |
| `bloom_filter` | **12.421** | 12.466 | 12.768 | 2119.027 | 5509.258 |
| `hash_join` | **20.663** | 21.991 | 22.054 | 2641.968 | 6087.191 |
| `sieve` | 33.002 | **32.585** | 32.838 | 75.734 | 2377.519 |
| `fib` | **24.592** | 26.196 | 25.388 | 99.023 | 779.569 |
| `collatz` | **12.879** | 13.098 | 13.948 | 51.672 | 492.902 |
| `matmul` | **17.234** | 17.593 | 17.696 | 64.058 | 2173.274 |
| `json_parse` | 7.832 | **6.492** | 8.218 | 28.305 | 29.126 |
| `nbody` | **19.310** | 27.387 | 19.365 | 70.887 | 1928.241 |

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
| _(floor: empty program)_ | _2.511_ | _69.651_ | _**72.162**_ | _42.662_ | _51.142_ | _51.614_ |
| `lcg` | 36.622 | 110.926 | **147.548** | 78.093 | 57.856 | 56.968 |
| `packet_classifier` | 2.907 | 78.971 | **81.878** | 43.111 | 62.848 | 56.551 |
| `ring_write` | 3.224 | 83.671 | **86.895** | 45.867 | 65.640 | 59.764 |
| `histogram_bins` | 3.094 | 82.459 | **85.553** | 41.775 | 75.774 | 64.901 |
| `prefix_scan` | 3.161 | 79.853 | **83.014** | 42.175 | 65.666 | 61.088 |
| `binary_search` | 3.647 | 85.454 | **89.101** | 47.726 | 69.576 | 65.784 |
| `sort_window` | 3.548 | 80.654 | **84.202** | 42.729 | 69.963 | 68.533 |
| `bloom_filter` | 3.921 | 82.159 | **86.080** | 45.112 | 68.752 | 63.469 |
| `hash_join` | 7.678 | 190.491 | **198.169** | 51.326 | 160.960 | 107.865 |
| `sieve` | 3.298 | 79.769 | **83.067** | 43.688 | 69.431 | 67.768 |
| `fib` | 2.919 | 75.996 | **78.915** | 41.984 | 61.257 | 54.889 |
| `collatz` | 3.215 | 84.159 | **87.374** | 45.107 | 65.520 | 59.061 |
| `matmul` | 3.727 | 80.409 | **84.136** | 44.220 | 74.733 | 80.150 |
| `json_parse` | 85.097 | 358.913 | **444.010** | 130.771 | 118.107 | 161.927 |
| `nbody` | 5.259 | 96.857 | **102.116** | 47.128 | 96.356 | 86.874 |

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
