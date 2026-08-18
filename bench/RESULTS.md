# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-18T20:16:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ef545466463b5c66470d567598fe2bfca1d0b9cd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32180912754 |
| NURL | `v0.44.2-25-gef545466` |
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
| _(floor: empty program)_ | _1.830_ | _1.883_ | _2.052_ | _24.771_ | _18.398_ |
| `lcg` | **44.409** | 44.474 | 44.579 | 1820.424 | 5385.771 |
| `packet_classifier` | **63.847** | 63.888 | 64.083 | 158.834 | 4690.177 |
| `ring_write` | **47.841** | 47.947 | 48.108 | 73.988 | 6575.258 |
| `histogram_bins` | 45.010 | **45.002** | 45.196 | 75.894 | 6483.461 |
| `prefix_scan` | **24.698** | 24.756 | 24.869 | 72.703 | 4875.203 |
| `binary_search` | **34.522** | 36.170 | 46.324 | 113.044 | 6367.820 |
| `sort_window` | **30.292** | 31.128 | 30.573 | 171.793 | 12058.364 |
| `bloom_filter` | **19.927** | 20.636 | 20.916 | 2746.015 | 7787.867 |
| `hash_join` | **27.816** | 31.051 | 31.389 | 3499.028 | 8327.648 |
| `sieve` | **20.795** | 20.861 | 21.182 | 71.825 | 3356.843 |
| `fib` | **28.350** | 33.697 | 29.791 | 148.638 | 1289.334 |
| `collatz` | 14.157 | **14.043** | 14.121 | 53.230 | 752.856 |
| `matmul` | 46.505 | 46.676 | **45.917** | 85.087 | 3367.106 |
| `json_parse` | **9.011** | 9.183 | 12.436 | 39.332 | 38.667 |
| `nbody` | **26.988** | 46.401 | 44.231 | 97.673 | 3142.806 |

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
| _(floor: empty program)_ | _3.285_ | _101.214_ | _**104.499**_ | _67.256_ | _66.436_ | _68.256_ |
| `lcg` | 3.385 | 103.952 | **107.337** | 66.235 | 74.313 | 75.488 |
| `packet_classifier` | 3.462 | 101.811 | **105.273** | 65.276 | 75.200 | 74.723 |
| `ring_write` | 3.588 | 104.579 | **108.167** | 66.064 | 76.487 | 76.433 |
| `histogram_bins` | 3.621 | 123.795 | **127.416** | 65.880 | 78.187 | 80.145 |
| `prefix_scan` | 3.665 | 110.759 | **114.424** | 67.031 | 82.497 | 80.232 |
| `binary_search` | 3.838 | 116.166 | **120.004** | 67.914 | 79.152 | 83.368 |
| `sort_window` | 3.887 | 118.524 | **122.411** | 67.467 | 84.386 | 86.398 |
| `bloom_filter` | 4.104 | 111.135 | **115.239** | 65.602 | 82.898 | 87.460 |
| `hash_join` | 6.616 | 256.133 | **262.749** | 69.043 | 126.211 | 118.613 |
| `sieve` | 3.801 | 109.986 | **113.787** | 68.055 | 86.965 | 88.730 |
| `fib` | 3.446 | 105.896 | **109.342** | 67.484 | 77.114 | 77.180 |
| `collatz` | 3.604 | 106.523 | **110.127** | 66.831 | 77.774 | 77.914 |
| `matmul` | 3.948 | 111.158 | **115.106** | 66.906 | 88.428 | 102.861 |
| `json_parse` | 51.502 | 420.084 | **471.586** | 115.404 | 127.383 | 189.872 |
| `nbody` | 5.271 | 134.706 | **139.977** | 68.758 | 101.836 | 100.859 |

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
