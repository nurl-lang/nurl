# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-28T20:04:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `ed6085af1db241f1b483407730c8f75fb21f496d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36476092023 |
| NURL | `v0.67.0` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
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
| _(floor: empty program)_ | _1.107_ | _1.075_ | _1.237_ | _17.077_ | _12.287_ |
| `lcg` | **29.083** | 29.865 | 29.487 | 1119.471 | 3054.336 |
| `packet_classifier` | **41.672** | 41.947 | 42.336 | 129.395 | 2617.575 |
| `ring_write` | 28.453 | 28.422 | **28.349** | 48.281 | 3739.552 |
| `histogram_bins` | **28.339** | 29.336 | 28.382 | 49.005 | 3345.526 |
| `prefix_scan` | **15.862** | 15.907 | 16.191 | 46.917 | 2478.836 |
| `binary_search` | 15.140 | **14.823** | 15.555 | 70.213 | 3772.103 |
| `sort_window` | 20.583 | **20.147** | 20.246 | 135.614 | 6846.960 |
| `bloom_filter` | 8.841 | 8.812 | **8.730** | 1653.276 | 4552.056 |
| `hash_join` | **15.755** | 17.178 | 17.362 | 1863.221 | 4533.337 |
| `sieve` | 11.841 | **11.530** | 11.683 | 44.300 | 1719.048 |
| `fib` | 18.607 | **18.314** | 18.955 | 75.367 | 667.380 |
| `collatz` | 9.160 | **8.991** | 9.136 | 36.085 | 408.464 |
| `matmul` | **19.550** | 20.966 | 20.256 | 52.489 | 1727.856 |
| `json_parse` | **4.750** | 5.080 | 6.679 | 24.535 | 24.284 |
| `nbody` | **16.252** | 24.060 | 16.349 | 57.993 | 1453.430 |

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
| _(floor: empty program)_ | _2.817_ | _77.646_ | _**80.463**_ | _47.575_ | _65.097_ | _47.358_ |
| `lcg` | 2.690 | 80.594 | **83.284** | 45.265 | 69.342 | 54.907 |
| `packet_classifier` | 2.920 | 85.051 | **87.971** | 48.009 | 73.258 | 56.580 |
| `ring_write` | 3.026 | 84.423 | **87.449** | 46.809 | 69.726 | 56.415 |
| `histogram_bins` | 3.003 | 86.885 | **89.888** | 45.830 | 79.160 | 63.507 |
| `prefix_scan` | 3.230 | 85.263 | **88.493** | 46.953 | 77.635 | 62.407 |
| `binary_search` | 3.192 | 82.866 | **86.058** | 45.850 | 74.608 | 59.893 |
| `sort_window` | 3.411 | 85.204 | **88.615** | 46.665 | 80.502 | 63.281 |
| `bloom_filter` | 3.802 | 89.135 | **92.937** | 48.807 | 77.000 | 60.899 |
| `hash_join` | 6.332 | 173.085 | **179.417** | 52.564 | 144.891 | 95.958 |
| `sieve` | 3.214 | 84.292 | **87.506** | 47.950 | 80.625 | 62.548 |
| `fib` | 2.732 | 80.980 | **83.712** | 46.507 | 69.284 | 54.742 |
| `collatz` | 2.975 | 84.569 | **87.544** | 47.186 | 83.637 | 60.234 |
| `matmul` | 3.426 | 83.265 | **86.691** | 45.875 | 79.941 | 72.912 |
| `json_parse` | 59.672 | 267.420 | **327.092** | 103.133 | 111.043 | 130.515 |
| `nbody` | 4.416 | 92.107 | **96.523** | 46.991 | 91.458 | 80.546 |

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
