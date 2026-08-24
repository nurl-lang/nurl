# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-24T16:16:07Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `63da00f8452c2bd088cb11423879ccd39afe3ce3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32749358808 |
| NURL | `v0.50.0-18-g63da00f8` |
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
| _(floor: empty program)_ | _1.538_ | _1.524_ | _1.767_ | _26.291_ | _18.435_ |
| `lcg` | **44.132** | 44.133 | 44.338 | 1816.789 | 5321.033 |
| `packet_classifier` | **63.474** | 63.479 | 63.726 | 158.648 | 4902.834 |
| `ring_write` | 47.605 | **47.594** | 47.926 | 73.398 | 6778.231 |
| `histogram_bins` | **44.563** | 44.588 | 44.803 | 75.073 | 6748.163 |
| `prefix_scan` | 24.475 | **24.422** | 24.748 | 73.329 | 4700.373 |
| `binary_search` | **33.615** | 35.844 | 36.630 | 111.960 | 6236.814 |
| `sort_window` | 29.894 | **29.831** | 30.102 | 165.380 | 11145.008 |
| `bloom_filter` | 19.645 | **18.675** | 20.608 | 2729.258 | 7874.806 |
| `hash_join` | **27.571** | 28.579 | 29.987 | 3421.875 | 8355.062 |
| `sieve` | 20.283 | **20.058** | 20.139 | 72.690 | 3371.039 |
| `fib` | **27.875** | 33.124 | 28.077 | 142.208 | 1293.635 |
| `collatz` | 13.719 | **13.606** | 13.873 | 52.555 | 752.607 |
| `matmul` | **45.374** | 46.016 | 45.801 | 83.038 | 3357.442 |
| `json_parse` | **8.736** | 8.738 | 12.028 | 38.703 | 38.244 |
| `nbody` | 26.616 | 44.973 | **26.209** | 97.768 | 3372.635 |

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
| _(floor: empty program)_ | _2.944_ | _99.802_ | _**102.746**_ | _63.049_ | _89.193_ | _58.374_ |
| `lcg` | 3.109 | 103.797 | **106.906** | 63.420 | 98.660 | 64.973 |
| `packet_classifier` | 3.216 | 104.831 | **108.047** | 65.202 | 99.427 | 65.519 |
| `ring_write` | 3.334 | 107.017 | **110.351** | 65.261 | 100.915 | 65.623 |
| `histogram_bins` | 3.411 | 125.504 | **128.915** | 65.869 | 116.046 | 73.686 |
| `prefix_scan` | 3.467 | 111.269 | **114.736** | 66.249 | 107.330 | 70.557 |
| `binary_search` | 3.617 | 114.191 | **117.808** | 66.285 | 103.283 | 72.155 |
| `sort_window` | 3.638 | 113.091 | **116.729** | 63.936 | 108.169 | 75.054 |
| `bloom_filter` | 3.935 | 112.110 | **116.045** | 65.939 | 107.056 | 71.586 |
| `hash_join` | 6.418 | 251.297 | **257.715** | 66.394 | 211.933 | 118.178 |
| `sieve` | 3.495 | 111.966 | **115.461** | 68.565 | 110.986 | 78.256 |
| `fib` | 3.155 | 105.983 | **109.138** | 64.246 | 98.202 | 62.732 |
| `collatz` | 3.321 | 106.781 | **110.102** | 65.709 | 99.708 | 67.681 |
| `matmul` | 3.724 | 110.425 | **114.149** | 65.665 | 114.103 | 90.111 |
| `json_parse` | 51.922 | 418.219 | **470.141** | 115.273 | 163.371 | 171.882 |
| `nbody` | 5.001 | 133.478 | **138.479** | 66.156 | 132.490 | 97.189 |

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
