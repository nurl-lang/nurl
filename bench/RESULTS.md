# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T08:49:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `3e734c10556be3853f2bed68f1cb540fd80dbaa5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41185727688 |
| NURL | `v0.82.0-10-g3e734c10` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.1 |
| Python | Python 3.14.4 |

| Setting | Value |
|---|---|
| NURL flags | `nurlc` → LLVM IR; `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` (ThinLTO backend at O3 — the standard `nurl.sh` release pipeline) |
| C flags | `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` — the identical pipeline, so neither column gets a backend the other lacks |
| Rust flags | `rustc -C opt-level=3` — rustc has no prelink/backend split; opt-level 3 is the `cargo build --release` default |
| Node / Python | `node` / `python3`, no flags |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |
| Workload scale | ×1 — the published contract (`--scale N` / `BENCH_SCALE=N` multiplies it) |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so a row's cells are timings of the
same computation. **Bold** is the fastest cell in the row; `n/a` is a
language the row is not implemented in (bench/manifest.tsv).

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.021_ | _2.873_ | _3.050_ | _23.166_ | _12.531_ |
| `lcg` | **35.968** | 36.011 | 36.071 | 1458.702 | 3965.003 |
| `packet_classifier` | 51.157 | **51.119** | 51.296 | 128.033 | 3384.007 |
| `ring_write` | 38.925 | 38.847 | **38.844** | 62.883 | 5131.740 |
| `histogram_bins` | **36.523** | 38.610 | 36.564 | 62.808 | 4479.977 |
| `prefix_scan` | 20.716 | **20.645** | 21.019 | 57.475 | 3296.516 |
| `binary_search` | 34.031 | **29.540** | 35.551 | 90.078 | 4747.077 |
| `sort_window` | 25.208 | **25.169** | 25.583 | 128.362 | 8501.008 |
| `bloom_filter` | **15.454** | 16.479 | 18.075 | 2113.789 | 6083.444 |
| `hash_join` | **22.891** | 22.927 | 25.540 | 2584.738 | 5728.103 |
| `sieve` | 20.839 | **20.775** | 20.906 | 63.063 | 2479.977 |
| `fib` | **23.620** | 27.846 | 27.986 | 118.086 | 869.076 |
| `collatz` | 12.533 | **12.443** | 12.712 | 46.577 | 546.534 |
| `matmul` | 38.156 | 38.132 | **37.666** | 64.018 | 2386.029 |
| `json_parse` | **8.173** | 10.942 | 15.342 | 34.446 | 28.909 |
| `nbody` | **22.470** | 37.017 | 22.944 | 79.841 | 2496.705 |
| `chacha20` | **8.547** | 38.974 | 29.680 | n/a | n/a |
| `poly1305` | **11.826** | 33.362 | 20.605 | n/a | n/a |
| `blake2b` | **40.226** | 57.070 | 62.846 | n/a | n/a |
| `sha512` | 40.791 | **40.549** | 44.324 | n/a | n/a |
| `x25519` | **29.459** | 44.265 | 45.355 | n/a | n/a |

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
| _(floor: empty program)_ | _5.999_ | _103.645_ | _**109.644**_ | _57.543_ | _72.267_ | _57.506_ |
| `lcg` | 6.049 | 111.512 | **117.561** | 58.046 | 80.665 | 62.536 |
| `packet_classifier` | 6.139 | 113.276 | **119.415** | 63.686 | 80.771 | 64.069 |
| `ring_write` | 14.362 | 116.033 | **130.395** | 66.603 | 84.830 | 67.023 |
| `histogram_bins` | 14.452 | 116.113 | **130.565** | 66.402 | 113.176 | 71.737 |
| `prefix_scan` | 14.313 | 117.387 | **131.700** | 65.968 | 87.385 | 68.541 |
| `binary_search` | 14.458 | 117.350 | **131.808** | 67.551 | 89.780 | 71.726 |
| `sort_window` | 14.444 | 121.816 | **136.260** | 68.966 | 98.320 | 76.827 |
| `bloom_filter` | 15.624 | 125.067 | **140.691** | 73.590 | 96.134 | 75.234 |
| `hash_join` | 17.738 | 214.277 | **232.015** | 71.501 | 174.466 | 108.930 |
| `sieve` | 14.501 | 122.554 | **137.055** | 69.190 | 97.575 | 78.776 |
| `fib` | 6.522 | 118.378 | **124.900** | 61.049 | 85.177 | 70.334 |
| `collatz` | 6.344 | 118.151 | **124.495** | 59.576 | 87.477 | 67.974 |
| `matmul` | 14.610 | 117.726 | **132.336** | 67.231 | 97.077 | 85.544 |
| `json_parse` | 41.084 | 354.384 | **395.468** | 94.899 | 134.250 | 150.601 |
| `nbody` | 16.510 | 126.490 | **143.000** | 71.111 | 112.514 | 96.654 |
| `chacha20` | 45.004 | 599.467 | **644.471** | 99.350 | 124.896 | 107.078 |
| `poly1305` | 36.045 | 399.560 | **435.605** | 89.990 | 128.091 | 120.151 |
| `blake2b` | 33.312 | 270.364 | **303.676** | 88.203 | 126.775 | 118.127 |
| `sha512` | 32.031 | 354.810 | **386.841** | 85.400 | 120.330 | 103.758 |
| `x25519` | 43.737 | 1178.559 | **1222.296** | 97.701 | 947.630 | 422.173 |

## 3. Correctness gate

Each row is timed only when all of its implementations print the same
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
| `chacha20` | `3720502699256473595` | identical across 3 languages |
| `poly1305` | `2498856793803813402` | identical across 3 languages |
| `blake2b` | `8590291023788228918` | identical across 3 languages |
| `sha512` | `7091519178481951668` | identical across 3 languages |
| `x25519` | `6127485567278337128` | identical across 3 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Nine of the original fifteen benchmarks are defined over 64-bit unsigned integers.
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
* `chacha20`, `poly1305`, `blake2b`, `sha512` and `x25519` are NURL / C /
  Rust only. Their NURL file is a driver around the standard library's own
  implementation (stdlib/std/chacha20poly1305.nu, hash_blake2b.nu,
  hash_sha512.nu, x25519.nu) — the row measures the stdlib a NURL program
  actually gets. C and Rust, whose standard libraries have none of the
  five, carry the same formulation written out by hand: Poly1305 at
  radix 2^64 and the donna-c64 X25519 field at radix 2^51, both with
  native 128-bit products. ChaCha20 is the one deliberate difference: C
  and Rust run the scalar RFC rounds, while the stdlib runs it on `v128`
  lanes (`v256` lanes in its x86-64-v3 clone). Each source names its
  RFC/FIPS test vector; x25519 at x1 reproduces RFC 7748's 1000-iteration
  value.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
