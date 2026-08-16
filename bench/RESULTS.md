# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T11:19:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `8fc14e029c37239d5adf1acc4e46632439cc7249` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31943808593 |
| NURL | `v0.44.0` |
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
| _(floor: empty program)_ | _1.676_ | _1.732_ | _1.872_ | _23.702_ | _18.023_ |
| `lcg` | **39.310** | 39.541 | 39.583 | 2051.060 | 5081.269 |
| `packet_classifier` | **56.700** | 56.759 | 56.881 | 162.207 | 4294.485 |
| `ring_write` | **42.486** | 42.719 | 42.689 | 68.319 | 6361.356 |
| `histogram_bins` | **39.648** | 41.466 | 40.012 | 69.595 | 6024.873 |
| `prefix_scan` | **21.886** | 21.960 | 22.196 | 66.294 | 4539.451 |
| `binary_search` | **36.489** | 38.541 | 43.637 | 107.495 | 6547.673 |
| `sort_window` | **26.880** | 27.545 | 27.109 | 197.598 | 11210.215 |
| `bloom_filter` | **18.147** | 18.301 | 18.561 | 2898.678 | 7460.818 |
| `hash_join` | **27.350** | 30.512 | 30.332 | 3419.042 | 8285.070 |
| `sieve` | 21.330 | **20.978** | 21.172 | 68.423 | 3303.351 |
| `fib` | **25.392** | 30.163 | 28.370 | 132.570 | 1357.943 |
| `collatz` | 12.615 | **12.519** | 12.748 | 52.632 | 716.842 |
| `matmul` | 33.833 | **33.773** | 34.001 | 77.379 | 3010.546 |
| `json_parse` | 9.254 | **8.950** | 11.837 | 38.203 | 39.139 |
| `nbody` | **25.682** | 41.203 | 39.402 | 101.912 | 3082.899 |

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
| _(floor: empty program)_ | _2.791_ | _90.034_ | _**92.825**_ | _58.510_ | _57.694_ | _61.219_ |
| `lcg` | 3.109 | 93.765 | **96.874** | 59.422 | 66.776 | 68.105 |
| `packet_classifier` | 3.068 | 93.547 | **96.615** | 59.753 | 68.893 | 68.848 |
| `ring_write` | 3.212 | 96.353 | **99.565** | 60.399 | 71.247 | 72.578 |
| `histogram_bins` | 3.324 | 117.889 | **121.213** | 60.829 | 72.428 | 72.284 |
| `prefix_scan` | 3.318 | 100.037 | **103.355** | 59.744 | 74.504 | 72.444 |
| `binary_search` | 3.499 | 104.682 | **108.181** | 60.767 | 69.344 | 75.262 |
| `sort_window` | 3.582 | 108.764 | **112.346** | 60.801 | 77.283 | 79.923 |
| `bloom_filter` | 3.821 | 105.151 | **108.972** | 60.849 | 78.958 | 76.752 |
| `hash_join` | 6.254 | 258.635 | **264.889** | 62.840 | 121.827 | 115.052 |
| `sieve` | 3.305 | 99.829 | **103.134** | 60.413 | 80.131 | 80.481 |
| `fib` | 3.059 | 91.890 | **94.949** | 59.626 | 67.634 | 67.269 |
| `collatz` | 3.306 | 97.882 | **101.188** | 60.947 | 69.266 | 72.355 |
| `matmul` | 3.605 | 103.670 | **107.275** | 60.247 | 82.840 | 93.909 |
| `json_parse` | 52.639 | 441.906 | **494.545** | 112.444 | 127.863 | 183.709 |
| `nbody` | 4.934 | 130.474 | **135.408** | 62.197 | 99.471 | 94.126 |

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
