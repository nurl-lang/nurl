# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-12T21:48:06Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d9890eea9190bdfd8f5fa093c917e789de616025` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34720753215 |
| NURL | `v0.63.0-22-gd9890eea` |
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
| _(floor: empty program)_ | _1.458_ | _1.456_ | _1.725_ | _23.825_ | _17.699_ |
| `lcg` | **39.050** | 39.095 | 39.391 | 2060.198 | 5232.028 |
| `packet_classifier` | **56.362** | 56.418 | 56.493 | 162.215 | 4724.263 |
| `ring_write` | **42.229** | 42.281 | 42.515 | 68.149 | 6801.702 |
| `histogram_bins` | **39.644** | 40.763 | 39.804 | 67.135 | 6113.482 |
| `prefix_scan` | 21.874 | **21.803** | 21.919 | 67.448 | 4402.262 |
| `binary_search` | 39.518 | 38.336 | **37.268** | 108.845 | 6728.558 |
| `sort_window` | 26.730 | **26.715** | 26.914 | 199.283 | 11351.180 |
| `bloom_filter` | **16.819** | 17.908 | 18.491 | 2833.066 | 7653.640 |
| `hash_join` | **26.894** | 28.126 | 29.341 | 3417.612 | 8420.943 |
| `sieve` | 18.773 | 18.633 | **18.413** | 66.892 | 3293.809 |
| `fib` | **25.257** | 29.967 | 25.402 | 132.463 | 1373.800 |
| `collatz` | 12.372 | **12.334** | 12.605 | 51.890 | 729.136 |
| `matmul` | 33.670 | **33.359** | 34.200 | 77.378 | 3350.394 |
| `json_parse` | 10.115 | **8.668** | 11.627 | 36.879 | 41.018 |
| `nbody` | 25.293 | 40.132 | **24.181** | 100.840 | 3162.931 |

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
| _(floor: empty program)_ | _3.266_ | _101.243_ | _**104.509**_ | _62.119_ | _82.439_ | _62.771_ |
| `lcg` | 3.387 | 111.040 | **114.427** | 61.805 | 93.042 | 71.896 |
| `packet_classifier` | 3.476 | 110.258 | **113.734** | 61.237 | 91.607 | 68.788 |
| `ring_write` | 3.696 | 113.179 | **116.875** | 62.712 | 93.625 | 71.947 |
| `histogram_bins` | 3.750 | 120.930 | **124.680** | 62.125 | 110.690 | 77.858 |
| `prefix_scan` | 3.788 | 112.720 | **116.508** | 62.582 | 101.559 | 75.216 |
| `binary_search` | 4.072 | 111.465 | **115.537** | 61.709 | 95.921 | 77.167 |
| `sort_window` | 4.138 | 114.782 | **118.920** | 62.607 | 107.695 | 82.790 |
| `bloom_filter` | 4.628 | 116.458 | **121.086** | 63.286 | 104.252 | 79.580 |
| `hash_join` | 8.896 | 265.760 | **274.656** | 67.537 | 223.914 | 126.672 |
| `sieve` | 3.842 | 111.511 | **115.353** | 61.604 | 105.971 | 82.349 |
| `fib` | 3.449 | 110.507 | **113.956** | 61.673 | 92.306 | 69.071 |
| `collatz` | 3.669 | 114.115 | **117.784** | 61.910 | 95.124 | 73.887 |
| `matmul` | 4.326 | 112.809 | **117.135** | 62.567 | 107.417 | 94.491 |
| `json_parse` | 98.693 | 483.642 | **582.335** | 158.840 | 164.652 | 182.610 |
| `nbody` | 6.446 | 132.503 | **138.949** | 65.171 | 130.046 | 115.435 |

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
