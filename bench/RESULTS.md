# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-12T06:59:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `22df24e810f5ac97eda5a9250fc5fd489b825820` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34679349444 |
| NURL | `v0.63.0-16-g22df24e8` |
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
| _(floor: empty program)_ | _1.612_ | _1.621_ | _1.879_ | _26.175_ | _19.356_ |
| `lcg` | 44.361 | **44.272** | 44.467 | 1825.846 | 5374.254 |
| `packet_classifier` | 63.922 | **63.738** | 63.920 | 158.417 | 4665.007 |
| `ring_write` | **47.789** | 47.833 | 47.905 | 75.468 | 6562.849 |
| `histogram_bins` | 44.762 | **44.694** | 44.963 | 77.031 | 6235.059 |
| `prefix_scan` | 24.740 | **24.659** | 24.814 | 74.387 | 4714.066 |
| `binary_search` | 41.626 | **35.843** | 36.830 | 115.581 | 7724.312 |
| `sort_window` | 30.179 | **30.163** | 30.324 | 167.252 | 12001.503 |
| `bloom_filter` | **17.517** | 18.890 | 20.886 | 2747.249 | 7782.209 |
| `hash_join` | **27.760** | 29.028 | 30.365 | 3536.506 | 8283.715 |
| `sieve` | 20.861 | **20.645** | 20.737 | 72.684 | 3616.967 |
| `fib` | **27.968** | 33.271 | 28.197 | 144.303 | 1277.918 |
| `collatz` | 13.767 | **13.751** | 13.997 | 53.889 | 747.008 |
| `matmul` | **45.266** | 45.732 | 46.121 | 85.700 | 3433.232 |
| `json_parse` | 9.619 | **9.034** | 12.306 | 40.590 | 41.746 |
| `nbody` | 26.711 | 44.935 | **26.229** | 99.732 | 3293.731 |

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
| _(floor: empty program)_ | _3.540_ | _110.748_ | _**114.288**_ | _68.229_ | _91.963_ | _69.064_ |
| `lcg` | 3.763 | 120.703 | **124.466** | 68.537 | 101.819 | 82.708 |
| `packet_classifier` | 4.091 | 121.454 | **125.545** | 70.353 | 103.442 | 76.630 |
| `ring_write` | 4.161 | 122.952 | **127.113** | 69.868 | 104.605 | 82.670 |
| `histogram_bins` | 4.313 | 132.008 | **136.321** | 68.698 | 119.866 | 87.154 |
| `prefix_scan` | 4.406 | 124.283 | **128.689** | 71.518 | 110.555 | 82.196 |
| `binary_search` | 4.545 | 122.541 | **127.086** | 69.276 | 104.902 | 87.320 |
| `sort_window` | 4.769 | 126.891 | **131.660** | 70.849 | 116.610 | 92.512 |
| `bloom_filter` | 5.014 | 120.857 | **125.871** | 68.426 | 112.475 | 83.799 |
| `hash_join` | 9.505 | 263.377 | **272.882** | 74.408 | 221.072 | 135.270 |
| `sieve` | 4.257 | 121.264 | **125.521** | 68.761 | 112.855 | 88.070 |
| `fib` | 3.869 | 117.872 | **121.741** | 68.036 | 96.042 | 73.443 |
| `collatz` | 4.090 | 123.396 | **127.486** | 69.650 | 102.152 | 78.295 |
| `matmul` | 4.660 | 117.199 | **121.859** | 66.932 | 110.642 | 98.996 |
| `json_parse` | 98.142 | 462.353 | **560.495** | 162.248 | 164.737 | 184.994 |
| `nbody` | 6.715 | 138.813 | **145.528** | 68.282 | 131.093 | 109.425 |

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
