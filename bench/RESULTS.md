# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T12:22:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `bf90b155ac9fd189a2d8c22efce4703611310bd2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31005013687 |
| NURL | `v0.33.0-13-gbf90b155` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.1 |
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
| _(floor: empty program)_ | _1.254_ | _1.289_ | _1.378_ | _18.265_ | _13.500_ |
| `lcg` | 35.341 | **35.248** | 35.688 | 1307.774 | 3804.498 |
| `packet_classifier` | **56.183** | 61.783 | 60.108 | 145.751 | 3154.657 |
| `ring_write` | 38.518 | **38.511** | 39.189 | 56.482 | 4447.933 |
| `histogram_bins` | **36.043** | 36.135 | 36.095 | 60.492 | 4371.883 |
| `prefix_scan` | **19.602** | 19.972 | 19.940 | 56.053 | 3222.615 |
| `binary_search` | 30.899 | **28.479** | 39.488 | 99.438 | 5251.836 |
| `sort_window` | 36.707 | 46.201 | **35.632** | 158.583 | 8164.622 |
| `bloom_filter` | **12.554** | 12.652 | 12.775 | 2115.582 | 5742.116 |
| `hash_join` | **21.455** | 23.481 | 23.657 | 2640.872 | 6285.666 |
| `sieve` | 32.615 | 32.183 | **32.132** | 72.503 | 2404.598 |
| `fib` | 25.357 | 27.248 | **23.296** | 99.597 | 791.239 |
| `collatz` | **13.356** | 13.592 | 13.974 | 54.171 | 503.803 |
| `matmul` | 18.103 | 17.996 | **17.920** | 64.659 | 2154.045 |
| `json_parse` | **6.514** | 6.936 | 8.530 | 28.134 | 29.351 |
| `nbody` | 28.655 | 28.671 | **26.334** | 70.955 | 1892.227 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns. The floor row is what each
toolchain costs for a program that does nothing — for NURL that is
dominated by the LTO link every NURL binary pays for, so subtract it to
read the marginal cost of the benchmark itself. Node and Python have no
column here: they compile at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.398_ | _63.449_ | _**65.847**_ | _43.105_ | _51.658_ |
| `lcg` | 2.110 | 64.898 | **67.008** | 46.085 | 56.579 |
| `packet_classifier` | 2.523 | 69.223 | **71.746** | 54.002 | 57.521 |
| `ring_write` | 2.317 | 67.354 | **69.671** | 47.147 | 58.009 |
| `histogram_bins` | 2.390 | 67.958 | **70.348** | 49.001 | 59.293 |
| `prefix_scan` | 2.417 | 68.202 | **70.619** | 49.159 | 59.475 |
| `binary_search` | 2.468 | 73.395 | **75.863** | 48.775 | 64.758 |
| `sort_window` | 2.505 | 74.146 | **76.651** | 53.699 | 66.565 |
| `bloom_filter` | 2.697 | 72.966 | **75.663** | 54.075 | 60.022 |
| `hash_join` | 4.410 | 158.619 | **163.029** | 89.434 | 93.103 |
| `sieve` | 2.360 | 67.909 | **70.269** | 54.888 | 65.897 |
| `fib` | 2.194 | 64.989 | **67.183** | 47.376 | 58.144 |
| `collatz` | 2.286 | 67.499 | **69.785** | 48.701 | 58.494 |
| `matmul` | 2.523 | 71.567 | **74.090** | 58.763 | 80.189 |
| `json_parse` | 34.538 | 398.134 | **432.672** | 92.432 | 162.266 |
| `nbody` | 3.340 | 83.153 | **86.493** | 71.307 | 80.222 |

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
