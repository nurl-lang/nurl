# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-19T10:32:20Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `cadd8aaa7864d338a836ef7543f544215686448a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32242715725 |
| NURL | `v0.45.0-3-gcadd8aaa` |
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
| _(floor: empty program)_ | _1.662_ | _1.742_ | _1.881_ | _22.744_ | _17.382_ |
| `lcg` | **39.393** | 39.407 | 39.575 | 2052.506 | 5209.406 |
| `packet_classifier` | 56.574 | **56.512** | 56.916 | 164.088 | 4645.019 |
| `ring_write` | **42.471** | 42.544 | 42.649 | 66.773 | 6275.275 |
| `histogram_bins` | **39.717** | 41.500 | 39.989 | 67.231 | 6034.573 |
| `prefix_scan` | **21.963** | 22.029 | 22.190 | 67.051 | 4710.139 |
| `binary_search` | **36.532** | 38.674 | 43.604 | 106.134 | 6097.011 |
| `sort_window` | **26.912** | 27.538 | 27.011 | 197.751 | 12263.857 |
| `bloom_filter` | 18.360 | **18.321** | 18.789 | 2860.515 | 7624.459 |
| `hash_join` | **27.229** | 30.274 | 30.072 | 3464.691 | 8506.704 |
| `sieve` | 20.299 | 20.286 | **20.166** | 66.795 | 3185.283 |
| `fib` | **25.377** | 30.109 | 28.414 | 131.444 | 1355.617 |
| `collatz` | **12.523** | 12.546 | 12.746 | 50.276 | 715.902 |
| `matmul` | 34.282 | **34.106** | 34.516 | 79.015 | 3153.505 |
| `json_parse` | 9.420 | **9.119** | 12.180 | 35.939 | 39.459 |
| `nbody` | **25.327** | 41.016 | 39.309 | 101.078 | 3028.739 |

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
| _(floor: empty program)_ | _2.876_ | _94.576_ | _**97.452**_ | _58.956_ | _57.203_ | _60.251_ |
| `lcg` | 3.072 | 94.820 | **97.892** | 58.083 | 67.275 | 68.712 |
| `packet_classifier` | 3.171 | 97.107 | **100.278** | 59.298 | 69.027 | 69.072 |
| `ring_write` | 3.280 | 96.708 | **99.988** | 58.803 | 69.962 | 70.553 |
| `histogram_bins` | 3.307 | 116.143 | **119.450** | 59.106 | 71.337 | 71.865 |
| `prefix_scan` | 3.338 | 101.062 | **104.400** | 58.876 | 73.306 | 73.628 |
| `binary_search` | 3.553 | 106.062 | **109.615** | 59.780 | 71.357 | 76.782 |
| `sort_window` | 3.475 | 104.624 | **108.099** | 57.974 | 75.132 | 79.557 |
| `bloom_filter` | 3.790 | 102.467 | **106.257** | 60.406 | 83.469 | 84.499 |
| `hash_join` | 6.253 | 252.539 | **258.792** | 61.284 | 120.769 | 112.573 |
| `sieve` | 3.358 | 96.883 | **100.241** | 58.633 | 78.035 | 78.917 |
| `fib` | 3.076 | 93.048 | **96.124** | 57.568 | 66.968 | 67.475 |
| `collatz` | 3.197 | 98.634 | **101.831** | 59.862 | 70.169 | 71.453 |
| `matmul` | 3.741 | 104.415 | **108.156** | 61.598 | 83.293 | 94.734 |
| `json_parse` | 53.386 | 441.117 | **494.503** | 113.385 | 130.493 | 191.923 |
| `nbody` | 5.096 | 128.338 | **133.434** | 62.297 | 97.137 | 96.462 |

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
