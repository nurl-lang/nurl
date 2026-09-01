# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-01T11:41:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `743cde4bda8b1dd92e1bac2170c6cdcb3d5675ac` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33503342529 |
| NURL | `v0.57.0-21-g743cde4b` |
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
| _(floor: empty program)_ | _1.542_ | _1.557_ | _1.783_ | _25.149_ | _18.085_ |
| `lcg` | 44.075 | **44.027** | 44.199 | 1826.062 | 5568.988 |
| `packet_classifier` | **63.443** | 63.455 | 63.694 | 158.635 | 4539.276 |
| `ring_write` | 47.602 | **47.575** | 47.817 | 72.657 | 6776.059 |
| `histogram_bins` | **44.564** | 44.587 | 44.813 | 74.922 | 6322.381 |
| `prefix_scan` | 24.545 | **24.485** | 24.850 | 73.628 | 4742.321 |
| `binary_search` | 41.447 | **35.462** | 36.504 | 110.469 | 6211.007 |
| `sort_window` | 29.917 | **29.905** | 30.120 | 169.210 | 11143.208 |
| `bloom_filter` | 19.672 | **18.707** | 20.612 | 2788.928 | 7825.000 |
| `hash_join` | **27.743** | 28.775 | 30.268 | 3590.779 | 8807.789 |
| `sieve` | 20.481 | **19.890** | 20.058 | 70.957 | 3298.699 |
| `fib` | **27.802** | 33.148 | 28.050 | 142.829 | 1291.039 |
| `collatz` | **13.604** | 13.625 | 13.874 | 51.972 | 751.388 |
| `matmul` | **45.888** | 46.173 | 47.100 | 84.102 | 3399.560 |
| `json_parse` | **8.650** | 8.723 | 12.245 | 37.938 | 37.922 |
| `nbody` | 26.743 | 44.868 | **26.206** | 94.760 | 3260.109 |

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
| _(floor: empty program)_ | _2.951_ | _101.117_ | _**104.068**_ | _63.606_ | _86.132_ | _65.156_ |
| `lcg` | 3.139 | 114.020 | **117.159** | 64.592 | 97.774 | 75.571 |
| `packet_classifier` | 3.199 | 114.014 | **117.213** | 65.218 | 101.747 | 74.774 |
| `ring_write` | 3.315 | 115.301 | **118.616** | 65.115 | 99.939 | 75.761 |
| `histogram_bins` | 3.485 | 126.212 | **129.697** | 65.200 | 115.192 | 84.142 |
| `prefix_scan` | 3.497 | 134.142 | **137.639** | 66.982 | 107.625 | 79.237 |
| `binary_search` | 3.598 | 115.937 | **119.535** | 66.118 | 101.953 | 81.061 |
| `sort_window` | 3.649 | 118.331 | **121.980** | 64.782 | 109.173 | 85.009 |
| `bloom_filter` | 3.953 | 118.903 | **122.856** | 64.913 | 108.385 | 81.425 |
| `hash_join` | 6.405 | 254.504 | **260.909** | 67.672 | 215.618 | 128.669 |
| `sieve` | 3.501 | 117.670 | **121.171** | 66.504 | 111.815 | 87.232 |
| `fib` | 3.158 | 111.347 | **114.505** | 63.658 | 95.626 | 72.949 |
| `collatz` | 3.329 | 116.755 | **120.084** | 64.505 | 98.951 | 75.635 |
| `matmul` | 3.698 | 118.807 | **122.505** | 66.830 | 114.209 | 104.026 |
| `json_parse` | 53.736 | 423.529 | **477.265** | 115.752 | 160.913 | 183.501 |
| `nbody` | 5.112 | 133.933 | **139.045** | 66.239 | 129.864 | 108.378 |

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
