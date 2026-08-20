# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T13:38:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `53fe142455fdfe8ef5663b62157cfbeb286e1159` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32374951412 |
| NURL | `v0.46.0-7-g53fe1424` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `clang -O2 -flto=thin` + ThinLTO backend O3, Rust `-C opt-level=3` |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.955_ | _2.045_ | _2.227_ | _23.564_ | _17.585_ |
| `lcg` | 40.501 | **39.529** | 40.187 | 2111.854 | 5141.804 |
| `packet_classifier` | 57.079 | **57.006** | 57.171 | 166.751 | 4475.690 |
| `ring_write` | 43.986 | **42.809** | 43.196 | 71.324 | 6084.128 |
| `histogram_bins` | 40.776 | 41.204 | **40.448** | 69.472 | 6010.627 |
| `prefix_scan` | 22.054 | **21.928** | 22.799 | 72.798 | 4482.880 |
| `binary_search` | **37.583** | 39.537 | 41.099 | 112.453 | 6312.493 |
| `sort_window` | **27.327** | 27.530 | 27.646 | 200.805 | 11228.349 |
| `bloom_filter` | 19.219 | **18.779** | 18.882 | 2868.548 | 7672.093 |
| `hash_join` | **27.531** | 28.887 | 30.803 | 3461.211 | 8323.664 |
| `sieve` | 20.514 | 19.653 | **18.661** | 70.298 | 3382.191 |
| `fib` | **25.438** | 30.106 | 28.658 | 134.995 | 1389.966 |
| `collatz` | 12.904 | 13.228 | **12.778** | 55.167 | 713.358 |
| `matmul` | **34.343** | 34.780 | 34.516 | 81.040 | 3443.387 |
| `json_parse` | 10.354 | **9.143** | 12.306 | 40.248 | 39.986 |
| `nbody` | 25.991 | 39.958 | **24.966** | 103.404 | 2993.666 |

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
| _(floor: empty program)_ | _3.441_ | _110.135_ | _**113.576**_ | _67.724_ | _92.993_ | _82.719_ |
| `lcg` | 3.588 | 107.323 | **110.911** | 67.045 | 97.996 | 85.601 |
| `packet_classifier` | 3.162 | 109.393 | **112.555** | 65.846 | 108.592 | 78.970 |
| `ring_write` | 3.492 | 108.247 | **111.739** | 65.679 | 106.229 | 89.173 |
| `histogram_bins` | 3.228 | 124.785 | **128.013** | 66.575 | 120.423 | 91.077 |
| `prefix_scan` | 3.471 | 112.623 | **116.094** | 67.286 | 113.155 | 92.238 |
| `binary_search` | 3.945 | 115.558 | **119.503** | 66.784 | 107.373 | 88.946 |
| `sort_window` | 4.018 | 119.347 | **123.365** | 67.923 | 117.784 | 104.133 |
| `bloom_filter` | 3.760 | 115.711 | **119.471** | 67.181 | 110.511 | 89.134 |
| `hash_join` | 6.411 | 275.125 | **281.536** | 67.621 | 233.660 | 135.886 |
| `sieve` | 4.357 | 112.612 | **116.969** | 68.372 | 116.922 | 95.318 |
| `fib` | 3.150 | 105.636 | **108.786** | 68.100 | 99.337 | 84.211 |
| `collatz` | 3.226 | 102.659 | **105.885** | 65.465 | 99.004 | 80.866 |
| `matmul` | 3.574 | 112.325 | **115.899** | 66.146 | 118.209 | 108.119 |
| `json_parse` | 54.907 | 457.585 | **512.492** | 121.850 | 175.008 | 214.464 |
| `nbody` | 4.805 | 137.506 | **142.311** | 66.286 | 138.876 | 116.958 |

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
