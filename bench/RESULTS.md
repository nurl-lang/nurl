# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T19:56:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `8067a7c898625b4524286862254b804a32a8be8d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31968864334 |
| NURL | `v0.44.2-3-g8067a7c8` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `clang -O2`, Rust `-C opt-level=2` |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.283_ | _1.325_ | _1.382_ | _19.772_ | _14.287_ |
| `lcg` | 35.836 | **35.658** | 36.156 | 1420.202 | 3951.916 |
| `packet_classifier` | 61.111 | 63.415 | **60.882** | 148.894 | 3211.189 |
| `ring_write` | 40.461 | 40.212 | **40.170** | 59.249 | 4687.400 |
| `histogram_bins` | **37.932** | 38.246 | 38.291 | 63.887 | 4522.100 |
| `prefix_scan` | 20.879 | **20.356** | 21.518 | 64.130 | 3395.005 |
| `binary_search` | **24.254** | 28.391 | 41.705 | 104.637 | 5089.752 |
| `sort_window` | **37.249** | 47.212 | 38.014 | 165.903 | 8979.868 |
| `bloom_filter` | 14.299 | **13.628** | 13.986 | 2262.984 | 6165.730 |
| `hash_join` | **22.778** | 24.781 | 24.467 | 2784.878 | 6683.124 |
| `sieve` | **34.557** | 35.619 | 35.490 | 80.984 | 2545.092 |
| `fib` | 26.333 | 26.456 | **23.176** | 101.014 | 806.824 |
| `collatz` | **13.501** | 14.277 | 14.341 | 57.757 | 531.177 |
| `matmul` | 22.000 | 19.549 | **18.963** | 66.708 | 2284.617 |
| `json_parse` | **6.884** | 7.121 | 8.857 | 29.287 | 30.599 |
| `nbody` | **20.618** | 29.901 | 27.638 | 74.178 | 1897.340 |

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
| _(floor: empty program)_ | _2.314_ | _72.549_ | _**74.863**_ | _52.318_ | _45.388_ | _56.117_ |
| `lcg` | 2.425 | 78.960 | **81.385** | 49.330 | 55.927 | 63.522 |
| `packet_classifier` | 2.501 | 76.499 | **79.000** | 47.183 | 52.629 | 60.424 |
| `ring_write` | 2.597 | 75.604 | **78.201** | 47.420 | 51.257 | 61.968 |
| `histogram_bins` | 2.697 | 90.784 | **93.481** | 46.803 | 55.762 | 64.518 |
| `prefix_scan` | 2.893 | 85.105 | **87.998** | 50.226 | 62.033 | 65.178 |
| `binary_search` | 2.893 | 85.986 | **88.879** | 50.153 | 65.071 | 69.234 |
| `sort_window` | 3.059 | 90.148 | **93.207** | 50.411 | 66.248 | 75.170 |
| `bloom_filter` | 3.288 | 88.247 | **91.535** | 51.477 | 66.314 | 71.558 |
| `hash_join` | 5.081 | 201.603 | **206.684** | 50.598 | 96.882 | 100.134 |
| `sieve` | 2.918 | 82.906 | **85.824** | 50.599 | 66.075 | 74.767 |
| `fib` | 2.496 | 74.700 | **77.196** | 47.939 | 55.882 | 60.681 |
| `collatz` | 2.652 | 77.756 | **80.408** | 47.164 | 55.331 | 62.852 |
| `matmul` | 2.810 | 82.598 | **85.408** | 49.997 | 222.426 | 86.794 |
| `json_parse` | 43.992 | 346.807 | **390.799** | 90.814 | 99.214 | 172.253 |
| `nbody` | 3.849 | 100.981 | **104.830** | 50.074 | 79.224 | 85.030 |

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
