# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-24T19:58:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `19d680588fff84bf78f2c2cb59f336250602ce5a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32770749602 |
| NURL | `v0.50.0-27-g19d68058` |
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
| _(floor: empty program)_ | _1.460_ | _1.458_ | _1.630_ | _24.393_ | _17.858_ |
| `lcg` | **39.109** | 39.134 | 39.356 | 2085.046 | 5381.266 |
| `packet_classifier` | 56.285 | **56.269** | 56.545 | 161.558 | 4609.951 |
| `ring_write` | 42.236 | **42.213** | 42.340 | 66.667 | 6097.736 |
| `histogram_bins` | **39.374** | 40.604 | 39.698 | 65.457 | 6008.108 |
| `prefix_scan` | 21.700 | **21.594** | 21.740 | 65.696 | 4525.348 |
| `binary_search` | **36.125** | 38.152 | 36.959 | 107.743 | 5951.043 |
| `sort_window` | **26.677** | 26.807 | 26.876 | 198.232 | 11978.738 |
| `bloom_filter` | **17.897** | 17.905 | 18.385 | 2834.748 | 7768.266 |
| `hash_join` | **26.713** | 27.899 | 29.326 | 3406.507 | 8472.135 |
| `sieve` | 20.209 | **19.817** | 20.187 | 67.301 | 3461.841 |
| `fib` | **25.068** | 29.724 | 25.189 | 131.480 | 1358.790 |
| `collatz` | 12.290 | **12.203** | 12.326 | 50.397 | 713.757 |
| `matmul` | 33.676 | **33.515** | 33.678 | 76.786 | 3200.051 |
| `json_parse` | 8.914 | **8.580** | 11.724 | 35.339 | 37.549 |
| `nbody` | 25.194 | 39.878 | **23.989** | 102.164 | 3033.784 |

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
| _(floor: empty program)_ | _2.700_ | _94.793_ | _**97.493**_ | _60.215_ | _81.473_ | _55.466_ |
| `lcg` | 2.877 | 99.315 | **102.192** | 60.508 | 92.569 | 60.612 |
| `packet_classifier` | 2.917 | 94.457 | **97.374** | 57.651 | 93.099 | 60.503 |
| `ring_write` | 2.949 | 97.122 | **100.071** | 58.459 | 91.875 | 61.743 |
| `histogram_bins` | 3.079 | 116.076 | **119.155** | 58.251 | 108.427 | 68.880 |
| `prefix_scan` | 3.103 | 99.301 | **102.404** | 58.334 | 96.197 | 64.189 |
| `binary_search` | 3.210 | 104.090 | **107.300** | 59.156 | 94.738 | 67.568 |
| `sort_window` | 3.357 | 110.643 | **114.000** | 61.079 | 106.199 | 73.889 |
| `bloom_filter` | 3.563 | 105.627 | **109.190** | 60.775 | 105.463 | 67.856 |
| `hash_join` | 5.987 | 256.125 | **262.112** | 61.717 | 219.560 | 114.937 |
| `sieve` | 3.086 | 98.938 | **102.024** | 58.242 | 102.096 | 71.401 |
| `fib` | 2.779 | 94.935 | **97.714** | 58.514 | 91.576 | 60.018 |
| `collatz` | 3.004 | 102.076 | **105.080** | 60.460 | 93.904 | 63.261 |
| `matmul` | 3.385 | 103.297 | **106.682** | 60.321 | 108.451 | 84.886 |
| `json_parse` | 52.815 | 438.413 | **491.228** | 110.804 | 163.114 | 167.006 |
| `nbody` | 4.627 | 126.156 | **130.783** | 60.697 | 126.937 | 92.225 |

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
