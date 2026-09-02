# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-02T11:55:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `053e060cbbc43c5dc1fda59a4eea19745a6a21c4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33626715845 |
| NURL | `v0.58.0-11-g053e060c` |
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
| _(floor: empty program)_ | _1.428_ | _1.405_ | _1.629_ | _22.160_ | _16.676_ |
| `lcg` | 38.965 | **38.950** | 39.124 | 2043.735 | 5352.259 |
| `packet_classifier` | 56.194 | **56.048** | 56.233 | 161.450 | 4403.225 |
| `ring_write` | 42.145 | **42.074** | 42.322 | 65.314 | 6130.085 |
| `histogram_bins` | **39.538** | 40.825 | 39.880 | 66.819 | 6876.841 |
| `prefix_scan` | **21.616** | 21.667 | 21.677 | 65.051 | 4596.785 |
| `binary_search` | 39.570 | 38.263 | **36.990** | 106.888 | 5985.134 |
| `sort_window` | **26.461** | 26.523 | 26.793 | 197.301 | 12147.211 |
| `bloom_filter` | **17.744** | 17.861 | 18.394 | 2860.093 | 7620.387 |
| `hash_join` | **26.784** | 27.923 | 29.250 | 3423.421 | 8145.760 |
| `sieve` | 18.395 | 18.128 | **17.795** | 65.275 | 3427.917 |
| `fib` | **25.122** | 29.665 | 25.191 | 130.844 | 1352.634 |
| `collatz` | 12.186 | **12.157** | 12.321 | 49.290 | 716.215 |
| `matmul` | 33.333 | **33.174** | 33.520 | 74.365 | 3120.749 |
| `json_parse` | 9.024 | **8.725** | 11.729 | 35.210 | 38.123 |
| `nbody` | 25.247 | 39.797 | **24.203** | 100.956 | 3066.379 |

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
| _(floor: empty program)_ | _2.607_ | _95.288_ | _**97.895**_ | _58.135_ | _78.413_ | _59.648_ |
| `lcg` | 2.718 | 103.550 | **106.268** | 57.541 | 87.620 | 67.688 |
| `packet_classifier` | 2.769 | 103.824 | **106.593** | 56.510 | 89.526 | 66.836 |
| `ring_write` | 2.908 | 104.490 | **107.398** | 57.393 | 90.068 | 69.067 |
| `histogram_bins` | 3.008 | 115.808 | **118.816** | 57.525 | 108.193 | 75.612 |
| `prefix_scan` | 3.044 | 107.593 | **110.637** | 57.321 | 94.673 | 72.878 |
| `binary_search` | 3.186 | 107.308 | **110.494** | 58.756 | 93.319 | 76.038 |
| `sort_window` | 3.288 | 110.546 | **113.834** | 58.688 | 104.309 | 79.692 |
| `bloom_filter` | 3.494 | 112.331 | **115.825** | 60.086 | 102.121 | 75.523 |
| `hash_join` | 6.025 | 257.904 | **263.929** | 63.372 | 216.096 | 131.541 |
| `sieve` | 3.050 | 104.221 | **107.271** | 56.983 | 99.762 | 78.742 |
| `fib` | 2.767 | 104.331 | **107.098** | 56.666 | 87.480 | 65.875 |
| `collatz` | 2.913 | 107.150 | **110.063** | 59.307 | 90.945 | 69.309 |
| `matmul` | 3.327 | 106.371 | **109.698** | 58.342 | 103.216 | 90.989 |
| `json_parse` | 56.810 | 449.864 | **506.674** | 112.785 | 158.754 | 173.024 |
| `nbody` | 4.651 | 129.073 | **133.724** | 59.963 | 126.650 | 98.412 |

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
