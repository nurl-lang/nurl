# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-14T23:10:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `ab0bf6c0b9003adc307618bc2af7f5b51d8b72fb` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34907252272 |
| NURL | `v0.65.0-20-gab0bf6c0` |
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
| _(floor: empty program)_ | _1.174_ | _1.142_ | _1.281_ | _22.155_ | _15.294_ |
| `lcg` | 37.349 | **37.286** | 37.422 | 1860.641 | 5299.786 |
| `packet_classifier` | **52.448** | 52.469 | 52.691 | 156.083 | 4320.329 |
| `ring_write` | 40.665 | **40.420** | 40.695 | 69.552 | 6287.872 |
| `histogram_bins` | 40.481 | 40.694 | **40.394** | 67.728 | 6119.199 |
| `prefix_scan` | 21.090 | 21.128 | **20.951** | 67.505 | 4905.846 |
| `binary_search` | 35.052 | 29.645 | **28.045** | 106.282 | 6509.132 |
| `sort_window` | 35.517 | **34.873** | 35.479 | 181.612 | 12955.977 |
| `bloom_filter` | 13.902 | 14.074 | **13.754** | 2805.997 | 7868.492 |
| `hash_join` | **24.805** | 24.970 | 26.792 | 3438.998 | 7974.020 |
| `sieve` | 35.405 | 35.547 | **35.124** | 82.353 | 3382.048 |
| `fib` | **25.439** | 26.231 | 25.537 | 121.597 | 1173.114 |
| `collatz` | 12.638 | 12.625 | **12.403** | 57.530 | 685.039 |
| `matmul` | **16.993** | 17.209 | 17.131 | 72.631 | 3015.311 |
| `json_parse` | 8.368 | **7.388** | 9.401 | 34.283 | 35.436 |
| `nbody` | 21.420 | 35.069 | **21.055** | 92.676 | 2436.919 |

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
| _(floor: empty program)_ | _2.677_ | _80.557_ | _**83.234**_ | _50.245_ | _65.237_ | _53.380_ |
| `lcg` | 2.861 | 90.368 | **93.229** | 49.914 | 73.839 | 62.437 |
| `packet_classifier` | 3.074 | 93.221 | **96.295** | 51.380 | 76.428 | 62.170 |
| `ring_write` | 3.230 | 93.297 | **96.527** | 51.559 | 76.178 | 63.740 |
| `histogram_bins` | 3.371 | 102.457 | **105.828** | 51.840 | 93.796 | 71.467 |
| `prefix_scan` | 3.329 | 95.059 | **98.388** | 51.627 | 81.574 | 71.922 |
| `binary_search` | 3.632 | 93.441 | **97.073** | 52.408 | 75.958 | 69.615 |
| `sort_window` | 3.781 | 96.665 | **100.446** | 52.130 | 86.813 | 74.138 |
| `bloom_filter` | 4.266 | 95.576 | **99.842** | 51.969 | 84.710 | 68.742 |
| `hash_join` | 8.451 | 229.255 | **237.706** | 56.332 | 189.924 | 116.153 |
| `sieve` | 3.410 | 92.587 | **95.997** | 51.295 | 86.049 | 73.982 |
| `fib` | 3.000 | 93.887 | **96.887** | 51.917 | 74.023 | 60.918 |
| `collatz` | 3.315 | 95.164 | **98.479** | 52.328 | 76.029 | 64.824 |
| `matmul` | 3.953 | 96.467 | **100.420** | 52.156 | 88.446 | 86.331 |
| `json_parse` | 97.532 | 413.456 | **510.988** | 147.867 | 137.419 | 169.661 |
| `nbody` | 5.784 | 110.556 | **116.340** | 53.879 | 109.764 | 96.086 |

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
