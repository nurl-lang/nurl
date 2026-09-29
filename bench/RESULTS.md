# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-29T19:23:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `4a42d7cb92d51868cc47e4da789b851d2efbc323` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36618393845 |
| NURL | `v0.67.0-3-g4a42d7cb` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
| Node | v22.23.3 |
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
| _(floor: empty program)_ | _1.171_ | _1.123_ | _1.292_ | _18.352_ | _12.782_ |
| `lcg` | **30.170** | 30.621 | 30.178 | 1149.246 | 3075.016 |
| `packet_classifier` | **43.059** | 43.873 | 44.118 | 133.825 | 2682.980 |
| `ring_write` | **31.185** | 31.560 | 31.527 | 54.240 | 3790.882 |
| `histogram_bins` | **31.488** | 31.508 | 31.975 | 53.827 | 3728.937 |
| `prefix_scan` | 17.105 | **17.038** | 17.319 | 50.900 | 2707.796 |
| `binary_search` | 16.196 | **16.078** | 16.878 | 75.836 | 3688.493 |
| `sort_window` | **21.326** | 21.485 | 21.898 | 144.015 | 6617.244 |
| `bloom_filter` | 9.148 | **9.128** | 9.302 | 1685.359 | 4536.200 |
| `hash_join` | **17.122** | 17.669 | 18.998 | 2083.487 | 4917.647 |
| `sieve` | 12.687 | **12.483** | 12.676 | 46.893 | 1943.244 |
| `fib` | 20.583 | **20.543** | 21.303 | 85.441 | 742.382 |
| `collatz` | 10.399 | **10.372** | 10.455 | 40.985 | 435.824 |
| `matmul` | **21.045** | 21.440 | 21.489 | 55.119 | 1980.063 |
| `json_parse` | **5.308** | 5.911 | 7.549 | 25.316 | 26.082 |
| `nbody` | 18.227 | 26.860 | **17.750** | 64.965 | 1550.923 |

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
| _(floor: empty program)_ | _3.009_ | _82.929_ | _**85.938**_ | _52.596_ | _70.401_ | _50.994_ |
| `lcg` | 3.027 | 90.410 | **93.437** | 51.691 | 76.114 | 60.993 |
| `packet_classifier` | 2.910 | 82.583 | **85.493** | 46.608 | 73.456 | 60.703 |
| `ring_write` | 3.051 | 83.710 | **86.761** | 47.922 | 76.645 | 60.230 |
| `histogram_bins` | 3.296 | 93.754 | **97.050** | 50.646 | 85.179 | 66.304 |
| `prefix_scan` | 3.345 | 88.835 | **92.180** | 50.061 | 83.266 | 63.982 |
| `binary_search` | 3.434 | 88.595 | **92.029** | 48.483 | 77.552 | 64.525 |
| `sort_window` | 3.651 | 90.448 | **94.099** | 49.325 | 82.169 | 68.565 |
| `bloom_filter` | 3.875 | 90.378 | **94.253** | 49.781 | 79.446 | 66.067 |
| `hash_join` | 6.506 | 173.351 | **179.857** | 55.692 | 145.709 | 99.177 |
| `sieve` | 3.530 | 93.266 | **96.796** | 51.712 | 82.746 | 68.874 |
| `fib` | 3.007 | 87.309 | **90.316** | 47.706 | 74.662 | 58.053 |
| `collatz` | 3.536 | 95.667 | **99.203** | 52.666 | 78.985 | 66.259 |
| `matmul` | 3.440 | 85.347 | **88.787** | 48.217 | 81.462 | 77.204 |
| `json_parse` | 68.317 | 307.727 | **376.044** | 116.172 | 121.258 | 151.099 |
| `nbody` | 5.215 | 104.128 | **109.343** | 53.139 | 102.646 | 88.551 |

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
