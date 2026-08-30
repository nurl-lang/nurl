# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-30T18:58:26Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `590230811fff539f9fb8a6ade5c1158da642420b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33329368734 |
| NURL | `v0.57.0` |
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
| _(floor: empty program)_ | _1.428_ | _1.457_ | _1.588_ | _21.873_ | _15.995_ |
| `lcg` | 37.850 | 38.887 | **36.514** | 1942.622 | 4943.304 |
| `packet_classifier` | **52.555** | 53.711 | 54.191 | 152.201 | 4260.952 |
| `ring_write` | **39.130** | 40.914 | 42.124 | 61.951 | 5863.197 |
| `histogram_bins` | **39.490** | 40.473 | 39.510 | 63.184 | 5794.557 |
| `prefix_scan` | 21.598 | **21.542** | 21.568 | 63.169 | 4642.310 |
| `binary_search` | 39.297 | 35.921 | **34.247** | 104.031 | 5769.317 |
| `sort_window` | **24.651** | 25.538 | 25.031 | 189.407 | 11089.030 |
| `bloom_filter` | **16.582** | 16.915 | 17.233 | 2684.557 | 7130.425 |
| `hash_join` | **26.609** | 27.668 | 27.363 | 3216.722 | 7894.409 |
| `sieve` | 17.177 | **16.969** | 17.579 | 60.031 | 3183.937 |
| `fib` | **24.168** | 28.631 | 24.756 | 120.914 | 1316.149 |
| `collatz` | **11.929** | 11.987 | 12.285 | 43.856 | 681.136 |
| `matmul` | **31.386** | 32.107 | 31.424 | 71.293 | 3049.760 |
| `json_parse` | 8.665 | **7.935** | 10.649 | 31.691 | 34.204 |
| `nbody` | 24.064 | 39.602 | **23.850** | 95.434 | 2882.360 |

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
| _(floor: empty program)_ | _2.412_ | _86.244_ | _**88.656**_ | _53.265_ | _71.729_ | _58.452_ |
| `lcg` | 2.597 | 97.267 | **99.864** | 52.967 | 80.356 | 64.200 |
| `packet_classifier` | 2.669 | 96.018 | **98.687** | 53.453 | 85.772 | 66.748 |
| `ring_write` | 2.927 | 100.367 | **103.294** | 53.826 | 82.745 | 68.923 |
| `histogram_bins` | 2.953 | 108.967 | **111.920** | 54.749 | 102.998 | 73.476 |
| `prefix_scan` | 2.948 | 97.065 | **100.013** | 54.071 | 87.518 | 68.684 |
| `binary_search` | 3.015 | 96.549 | **99.564** | 54.284 | 83.689 | 73.973 |
| `sort_window` | 3.028 | 101.523 | **104.551** | 54.535 | 94.913 | 76.750 |
| `bloom_filter` | 3.486 | 101.578 | **105.064** | 54.066 | 93.472 | 72.348 |
| `hash_join` | 5.858 | 238.423 | **244.281** | 58.005 | 202.121 | 118.091 |
| `sieve` | 3.101 | 101.196 | **104.297** | 56.147 | 93.112 | 74.549 |
| `fib` | 2.678 | 94.341 | **97.019** | 55.219 | 84.951 | 63.790 |
| `collatz` | 2.894 | 101.764 | **104.658** | 54.901 | 84.094 | 68.336 |
| `matmul` | 3.199 | 101.220 | **104.419** | 56.495 | 100.204 | 86.648 |
| `json_parse` | 50.560 | 410.342 | **460.902** | 104.186 | 150.829 | 164.400 |
| `nbody` | 4.306 | 118.884 | **123.190** | 55.699 | 115.530 | 98.688 |

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
