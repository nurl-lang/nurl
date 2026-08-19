# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-19T12:57:17Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `4e276754799e5168db80a554bd192523feb08ef7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32254983370 |
| NURL | `v0.45.0-5-g4e276754` |
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
| _(floor: empty program)_ | _1.675_ | _1.705_ | _1.837_ | _22.444_ | _17.041_ |
| `lcg` | **39.220** | 39.378 | 39.383 | 2044.107 | 5041.355 |
| `packet_classifier` | **56.316** | 56.537 | 56.503 | 160.411 | 4345.660 |
| `ring_write` | **42.421** | 42.427 | 42.692 | 66.378 | 6234.228 |
| `histogram_bins` | **39.861** | 41.440 | 39.866 | 66.319 | 6001.045 |
| `prefix_scan` | 21.973 | **21.951** | 22.126 | 64.213 | 4522.237 |
| `binary_search` | **36.398** | 38.412 | 43.349 | 106.657 | 6068.919 |
| `sort_window` | **26.786** | 27.445 | 26.927 | 197.242 | 11532.393 |
| `bloom_filter` | **18.025** | 18.316 | 18.547 | 2851.464 | 7651.687 |
| `hash_join` | **27.130** | 30.284 | 30.068 | 3407.471 | 8310.714 |
| `sieve` | 18.704 | **18.037** | 18.272 | 65.226 | 3365.877 |
| `fib` | **25.324** | 29.997 | 28.269 | 131.111 | 1393.034 |
| `collatz` | **12.429** | 12.446 | 12.567 | 48.207 | 722.574 |
| `matmul` | 33.603 | **33.548** | 33.804 | 75.815 | 3243.573 |
| `json_parse` | 9.087 | **8.791** | 11.715 | 33.824 | 37.501 |
| `nbody` | **25.242** | 40.981 | 39.015 | 99.808 | 2987.296 |

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
| _(floor: empty program)_ | _2.895_ | _89.688_ | _**92.583**_ | _57.338_ | _59.273_ | _60.912_ |
| `lcg` | 3.000 | 91.246 | **94.246** | 56.784 | 64.553 | 67.400 |
| `packet_classifier` | 3.065 | 92.784 | **95.849** | 56.851 | 65.598 | 68.692 |
| `ring_write` | 3.191 | 95.888 | **99.079** | 59.398 | 68.402 | 70.409 |
| `histogram_bins` | 3.252 | 110.585 | **113.837** | 56.818 | 69.194 | 71.872 |
| `prefix_scan` | 3.340 | 96.347 | **99.687** | 57.524 | 71.437 | 71.959 |
| `binary_search` | 3.446 | 99.571 | **103.017** | 57.745 | 67.495 | 72.819 |
| `sort_window` | 3.480 | 102.553 | **106.033** | 57.151 | 73.924 | 78.995 |
| `bloom_filter` | 3.762 | 99.350 | **103.112** | 57.713 | 74.395 | 79.782 |
| `hash_join` | 6.251 | 250.249 | **256.500** | 60.427 | 120.092 | 110.473 |
| `sieve` | 3.296 | 94.945 | **98.241** | 57.270 | 76.553 | 78.644 |
| `fib` | 3.058 | 92.962 | **96.020** | 57.982 | 65.360 | 67.236 |
| `collatz` | 3.225 | 95.904 | **99.129** | 57.804 | 67.248 | 69.703 |
| `matmul` | 3.591 | 98.244 | **101.835** | 57.649 | 79.367 | 91.021 |
| `json_parse` | 52.167 | 424.999 | **477.166** | 108.124 | 121.453 | 175.595 |
| `nbody` | 4.958 | 121.564 | **126.522** | 58.912 | 94.315 | 91.654 |

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
