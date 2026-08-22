# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-22T12:29:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `8b7fa8084035c1788e04e10aa0c379675444ebab` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32572891878 |
| NURL | `v0.49.0` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
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
| _(floor: empty program)_ | _1.442_ | _1.430_ | _1.637_ | _24.251_ | _18.584_ |
| `lcg` | 39.285 | **39.238** | 39.431 | 2058.551 | 5446.546 |
| `packet_classifier` | 56.475 | **56.353** | 56.606 | 161.531 | 4350.195 |
| `ring_write` | **42.172** | 42.279 | 42.534 | 66.832 | 6181.032 |
| `histogram_bins` | **39.725** | 40.775 | 39.827 | 68.501 | 5943.572 |
| `prefix_scan` | 21.660 | **21.645** | 22.036 | 67.649 | 4552.483 |
| `binary_search` | **36.411** | 38.476 | 37.258 | 107.362 | 6085.533 |
| `sort_window` | 26.798 | **26.768** | 26.813 | 199.231 | 11278.097 |
| `bloom_filter` | **17.959** | 18.011 | 18.564 | 2854.766 | 7530.699 |
| `hash_join` | **27.098** | 28.038 | 29.633 | 3432.116 | 8297.320 |
| `sieve` | 20.599 | 20.160 | **18.164** | 69.113 | 3644.124 |
| `fib` | **25.113** | 30.005 | 25.347 | 131.607 | 1363.609 |
| `collatz` | 12.253 | **12.243** | 12.425 | 50.990 | 716.809 |
| `matmul` | **33.709** | 33.750 | 33.961 | 76.235 | 3438.076 |
| `json_parse` | 8.925 | **8.630** | 11.768 | 37.865 | 38.714 |
| `nbody` | 25.225 | 39.864 | **24.327** | 102.105 | 3051.846 |

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
| _(floor: empty program)_ | _2.718_ | _94.386_ | _**97.104**_ | _58.845_ | _80.657_ | _54.925_ |
| `lcg` | 2.909 | 97.773 | **100.682** | 59.084 | 91.273 | 63.091 |
| `packet_classifier` | 2.865 | 96.969 | **99.834** | 59.459 | 95.654 | 61.356 |
| `ring_write` | 3.098 | 99.287 | **102.385** | 60.859 | 95.701 | 61.788 |
| `histogram_bins` | 3.054 | 116.614 | **119.668** | 60.037 | 112.994 | 69.921 |
| `prefix_scan` | 3.144 | 102.355 | **105.499** | 62.777 | 100.851 | 66.295 |
| `binary_search` | 3.387 | 106.310 | **109.697** | 60.946 | 96.625 | 67.875 |
| `sort_window` | 3.470 | 111.278 | **114.748** | 61.464 | 108.044 | 74.584 |
| `bloom_filter` | 3.560 | 106.134 | **109.694** | 60.804 | 104.111 | 67.312 |
| `hash_join` | 6.167 | 259.323 | **265.490** | 63.570 | 223.449 | 119.501 |
| `sieve` | 3.185 | 103.638 | **106.823** | 60.066 | 106.575 | 71.228 |
| `fib` | 2.839 | 96.266 | **99.105** | 60.756 | 94.590 | 59.680 |
| `collatz` | 3.124 | 100.172 | **103.296** | 61.023 | 94.242 | 64.373 |
| `matmul` | 3.376 | 103.453 | **106.829** | 60.253 | 109.140 | 85.968 |
| `json_parse` | 54.304 | 441.029 | **495.333** | 113.828 | 163.793 | 168.933 |
| `nbody` | 4.880 | 130.016 | **134.896** | 63.273 | 131.207 | 95.924 |

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
