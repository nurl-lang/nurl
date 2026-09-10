# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-10T19:37:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `bd62f04673a2f6ad9bf8e0fc2e5e0ca79d8eb111` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34521024681 |
| NURL | `v0.63.0-6-gbd62f046` |
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
| _(floor: empty program)_ | _1.599_ | _1.565_ | _1.818_ | _29.103_ | _18.969_ |
| `lcg` | 44.294 | **44.257** | 44.510 | 1829.126 | 5353.163 |
| `packet_classifier` | 63.693 | **63.537** | 63.793 | 161.333 | 4644.775 |
| `ring_write` | 47.715 | **47.643** | 47.895 | 74.630 | 6993.061 |
| `histogram_bins` | 44.831 | **44.822** | 44.884 | 76.610 | 6359.700 |
| `prefix_scan` | 24.535 | **24.458** | 24.768 | 73.688 | 4701.667 |
| `binary_search` | 41.562 | **35.867** | 36.795 | 115.123 | 6845.619 |
| `sort_window` | **29.896** | 29.983 | 30.231 | 167.030 | 11099.841 |
| `bloom_filter` | 19.830 | **19.025** | 20.967 | 2742.364 | 7965.306 |
| `hash_join` | **27.932** | 28.829 | 30.426 | 3410.713 | 8420.107 |
| `sieve` | 20.814 | **20.251** | 20.410 | 73.388 | 3517.471 |
| `fib` | 28.319 | 33.382 | **28.281** | 143.140 | 1286.560 |
| `collatz` | **13.894** | 13.984 | 14.058 | 56.691 | 753.558 |
| `matmul` | 46.230 | **45.416** | 46.581 | 86.941 | 3542.180 |
| `json_parse` | **8.943** | 8.965 | 12.312 | 39.617 | 41.297 |
| `nbody` | 27.038 | 45.072 | **26.498** | 98.886 | 3805.439 |

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
| _(floor: empty program)_ | _3.212_ | _112.430_ | _**115.642**_ | _69.484_ | _94.122_ | _71.063_ |
| `lcg` | 3.460 | 122.093 | **125.553** | 69.331 | 102.923 | 78.585 |
| `packet_classifier` | 3.292 | 118.860 | **122.152** | 67.860 | 104.142 | 76.285 |
| `ring_write` | 3.743 | 125.375 | **129.118** | 73.510 | 105.480 | 80.307 |
| `histogram_bins` | 3.634 | 130.791 | **134.425** | 68.507 | 119.279 | 90.089 |
| `prefix_scan` | 3.521 | 121.316 | **124.837** | 67.460 | 107.421 | 84.012 |
| `binary_search` | 3.749 | 125.147 | **128.896** | 69.645 | 106.220 | 84.698 |
| `sort_window` | 3.805 | 122.589 | **126.394** | 66.721 | 112.677 | 86.102 |
| `bloom_filter` | 4.199 | 135.166 | **139.365** | 70.980 | 116.314 | 96.319 |
| `hash_join` | 6.565 | 262.275 | **268.840** | 72.459 | 222.109 | 140.546 |
| `sieve` | 3.657 | 123.980 | **127.637** | 70.233 | 114.529 | 88.505 |
| `fib` | 3.275 | 119.478 | **122.753** | 68.558 | 102.916 | 75.428 |
| `collatz` | 3.555 | 126.654 | **130.209** | 68.842 | 107.573 | 85.640 |
| `matmul` | 3.787 | 122.331 | **126.118** | 69.310 | 117.410 | 102.080 |
| `json_parse` | 58.414 | 450.763 | **509.177** | 124.686 | 170.450 | 192.136 |
| `nbody` | 5.378 | 142.241 | **147.619** | 70.766 | 137.204 | 113.803 |

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
