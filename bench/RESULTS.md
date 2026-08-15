# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-15T18:23:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e1423a34556cdd6eb5c26aa6f308b73d6aa80fc7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31900770578 |
| NURL | `v0.43.0-4-ge1423a34` |
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
| _(floor: empty program)_ | _1.842_ | _1.960_ | _2.142_ | _26.996_ | _19.484_ |
| `lcg` | **44.580** | 44.616 | 44.731 | 1820.936 | 5436.819 |
| `packet_classifier` | **63.836** | 63.954 | 64.089 | 157.988 | 4961.702 |
| `ring_write` | **48.109** | 48.150 | 48.359 | 75.102 | 7404.482 |
| `histogram_bins` | **45.027** | 45.183 | 45.292 | 76.710 | 6437.027 |
| `prefix_scan` | **24.913** | 24.963 | 25.141 | 73.572 | 5090.206 |
| `binary_search` | **33.755** | 36.237 | 46.473 | 112.518 | 6462.291 |
| `sort_window` | **30.443** | 31.295 | 30.656 | 167.382 | 11541.257 |
| `bloom_filter` | **20.169** | 20.884 | 21.119 | 2789.934 | 7746.886 |
| `hash_join` | **28.105** | 31.225 | 31.582 | 3563.133 | 8220.631 |
| `sieve` | 21.374 | 21.366 | **21.206** | 73.177 | 3378.744 |
| `fib` | **28.425** | 33.634 | 29.831 | 144.468 | 1289.939 |
| `collatz` | **14.178** | 14.300 | 14.352 | 54.508 | 753.216 |
| `matmul` | **46.309** | 46.614 | 46.887 | 85.601 | 3454.680 |
| `json_parse` | **9.222** | 9.398 | 12.773 | 40.763 | 40.327 |
| `nbody` | **27.271** | 46.693 | 44.357 | 99.407 | 3301.187 |

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
| _(floor: empty program)_ | _3.204_ | _104.036_ | _**107.240**_ | _67.657_ | _68.667_ | _94.664_ |
| `lcg` | 3.394 | 105.772 | **109.166** | 67.809 | 77.329 | 77.968 |
| `packet_classifier` | 3.573 | 109.465 | **113.038** | 69.036 | 78.346 | 77.903 |
| `ring_write` | 3.719 | 110.376 | **114.095** | 69.145 | 80.001 | 80.292 |
| `histogram_bins` | 3.697 | 129.030 | **132.727** | 68.429 | 80.788 | 82.588 |
| `prefix_scan` | 3.704 | 113.161 | **116.865** | 68.836 | 83.138 | 81.581 |
| `binary_search` | 3.929 | 118.451 | **122.380** | 69.199 | 80.451 | 84.798 |
| `sort_window` | 3.948 | 121.164 | **125.112** | 69.342 | 87.420 | 89.763 |
| `bloom_filter` | 4.148 | 115.951 | **120.099** | 69.512 | 88.055 | 85.194 |
| `hash_join` | 6.786 | 265.421 | **272.207** | 72.990 | 126.990 | 121.495 |
| `sieve` | 3.803 | 111.719 | **115.522** | 68.253 | 88.914 | 159.490 |
| `fib` | 3.481 | 106.763 | **110.244** | 68.426 | 77.874 | 76.401 |
| `collatz` | 3.603 | 109.814 | **113.417** | 69.226 | 78.894 | 79.939 |
| `matmul` | 4.067 | 115.723 | **119.790** | 69.676 | 92.324 | 104.158 |
| `json_parse` | 49.544 | 435.665 | **485.209** | 116.640 | 132.819 | 198.065 |
| `nbody` | 5.262 | 140.302 | **145.564** | 70.728 | 105.399 | 105.751 |

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
