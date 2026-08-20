# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T11:49:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c699b091567282f6cf7609b3d9b2eaa1e958ffa1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32365320773 |
| NURL | `v0.46.0-4-gc699b091` |
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
| _(floor: empty program)_ | _1.549_ | _1.519_ | _1.772_ | _23.418_ | _17.716_ |
| `lcg` | **44.074** | 44.128 | 44.236 | 1816.720 | 5840.191 |
| `packet_classifier` | **63.554** | 63.556 | 63.756 | 159.271 | 4521.156 |
| `ring_write` | 47.582 | **47.548** | 47.760 | 73.631 | 6697.020 |
| `histogram_bins` | 44.647 | **44.585** | 44.802 | 74.666 | 6511.519 |
| `prefix_scan` | **24.371** | 24.387 | 24.603 | 70.761 | 4724.200 |
| `binary_search` | **33.960** | 35.574 | 41.598 | 112.053 | 6663.709 |
| `sort_window` | 29.940 | **29.922** | 30.172 | 172.133 | 11145.618 |
| `bloom_filter` | 19.676 | **18.676** | 20.632 | 2724.251 | 8131.978 |
| `hash_join` | **27.560** | 28.681 | 30.109 | 3399.459 | 8153.283 |
| `sieve` | 20.402 | **20.040** | 20.222 | 71.313 | 3461.624 |
| `fib` | **27.914** | 33.214 | 29.299 | 143.772 | 1290.078 |
| `collatz` | 13.687 | **13.659** | 13.792 | 51.170 | 755.089 |
| `matmul` | 45.895 | 46.338 | **45.677** | 83.757 | 3484.475 |
| `json_parse` | **8.667** | 8.788 | 12.284 | 38.351 | 38.094 |
| `nbody` | 26.722 | 44.881 | **26.243** | 95.403 | 3169.458 |

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
| _(floor: empty program)_ | _3.067_ | _100.268_ | _**103.335**_ | _64.129_ | _86.644_ | _66.231_ |
| `lcg` | 3.083 | 100.580 | **103.663** | 63.252 | 97.500 | 73.104 |
| `packet_classifier` | 3.169 | 102.905 | **106.074** | 64.687 | 100.448 | 75.000 |
| `ring_write` | 3.348 | 107.698 | **111.046** | 66.903 | 102.727 | 78.301 |
| `histogram_bins` | 3.475 | 123.833 | **127.308** | 65.533 | 116.179 | 93.305 |
| `prefix_scan` | 3.425 | 106.263 | **109.688** | 63.266 | 103.076 | 78.321 |
| `binary_search` | 3.581 | 110.237 | **113.818** | 64.135 | 99.127 | 78.733 |
| `sort_window` | 3.640 | 112.173 | **115.813** | 63.968 | 108.619 | 84.751 |
| `bloom_filter` | 3.905 | 108.039 | **111.944** | 63.771 | 105.961 | 79.800 |
| `hash_join` | 6.338 | 250.337 | **256.675** | 65.966 | 212.157 | 136.410 |
| `sieve` | 3.475 | 106.585 | **110.060** | 64.465 | 109.652 | 84.922 |
| `fib` | 3.155 | 102.517 | **105.672** | 63.540 | 96.655 | 72.894 |
| `collatz` | 3.351 | 104.998 | **108.349** | 63.933 | 99.166 | 76.031 |
| `matmul` | 3.690 | 106.237 | **109.927** | 63.691 | 110.370 | 97.488 |
| `json_parse` | 51.473 | 414.264 | **465.737** | 113.152 | 161.438 | 186.031 |
| `nbody` | 5.018 | 130.220 | **135.238** | 64.760 | 129.731 | 106.432 |

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
