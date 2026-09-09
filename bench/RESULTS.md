# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-09T16:51:20Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0849c5a41a5704b49fccf6b00cb25dbf42503fd5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34378826368 |
| NURL | `v0.62.0-6-g0849c5a4` |
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
| _(floor: empty program)_ | _1.556_ | _1.502_ | _1.743_ | _23.443_ | _17.775_ |
| `lcg` | 44.034 | **44.005** | 44.235 | 1813.134 | 5361.148 |
| `packet_classifier` | 63.385 | **63.381** | 63.615 | 157.467 | 4639.012 |
| `ring_write` | **47.546** | 47.675 | 47.830 | 73.609 | 8601.206 |
| `histogram_bins` | **44.495** | 44.507 | 44.768 | 74.493 | 6390.631 |
| `prefix_scan` | **24.373** | 24.375 | 24.605 | 71.699 | 4734.813 |
| `binary_search` | 41.375 | **35.567** | 36.568 | 110.657 | 8227.689 |
| `sort_window` | 29.911 | **29.829** | 30.081 | 166.303 | 12008.973 |
| `bloom_filter` | 19.685 | **18.624** | 20.644 | 2726.568 | 7862.097 |
| `hash_join` | **27.515** | 28.565 | 29.985 | 3464.604 | 8467.838 |
| `sieve` | 20.437 | **19.957** | 20.113 | 70.392 | 3387.600 |
| `fib` | **27.836** | 33.139 | 28.020 | 141.819 | 1316.969 |
| `collatz` | 13.676 | **13.594** | 13.790 | 50.995 | 746.373 |
| `matmul` | 45.937 | 45.853 | **45.836** | 83.463 | 3404.000 |
| `json_parse` | 8.806 | **8.765** | 12.068 | 36.761 | 39.701 |
| `nbody` | 26.711 | 44.905 | **26.215** | 96.193 | 3319.240 |

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
| _(floor: empty program)_ | _2.953_ | _102.869_ | _**105.822**_ | _65.119_ | _86.141_ | _56.648_ |
| `lcg` | 3.062 | 113.871 | **116.933** | 65.002 | 96.971 | 63.052 |
| `packet_classifier` | 3.189 | 114.165 | **117.354** | 64.668 | 97.624 | 63.227 |
| `ring_write` | 3.436 | 120.517 | **123.953** | 67.264 | 104.744 | 66.285 |
| `histogram_bins` | 3.357 | 126.319 | **129.676** | 66.776 | 115.536 | 72.204 |
| `prefix_scan` | 3.387 | 115.658 | **119.045** | 65.195 | 102.247 | 67.205 |
| `binary_search` | 3.562 | 115.021 | **118.583** | 64.772 | 99.303 | 69.612 |
| `sort_window` | 3.626 | 118.552 | **122.178** | 64.945 | 108.329 | 74.434 |
| `bloom_filter` | 3.873 | 119.028 | **122.901** | 65.163 | 107.530 | 69.964 |
| `hash_join` | 6.495 | 252.810 | **259.305** | 67.214 | 212.676 | 117.092 |
| `sieve` | 3.431 | 113.719 | **117.150** | 64.513 | 107.590 | 74.080 |
| `fib` | 3.185 | 113.445 | **116.630** | 64.336 | 94.383 | 62.191 |
| `collatz` | 3.299 | 116.016 | **119.315** | 64.736 | 100.105 | 64.918 |
| `matmul` | 3.649 | 115.437 | **119.086** | 64.999 | 109.625 | 86.654 |
| `json_parse` | 56.998 | 437.173 | **494.171** | 119.937 | 161.166 | 170.152 |
| `nbody` | 5.120 | 133.821 | **138.941** | 66.589 | 130.403 | 95.595 |

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
