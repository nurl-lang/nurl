# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-04T11:49:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `031fd6313659bcb8af238d3d5b2d8fbb0017d429` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33869405112 |
| NURL | `v0.60.0-2-g031fd631` |
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
| _(floor: empty program)_ | _1.144_ | _1.135_ | _1.247_ | _19.444_ | _11.844_ |
| `lcg` | **30.171** | 30.654 | 30.766 | 1057.275 | 3223.800 |
| `packet_classifier` | 52.323 | **51.904** | 52.076 | 125.298 | 2794.593 |
| `ring_write` | 32.781 | 33.156 | **32.654** | 49.898 | 3940.986 |
| `histogram_bins` | 31.246 | **31.196** | 31.292 | 51.705 | 3789.178 |
| `prefix_scan` | 16.582 | **16.545** | 16.906 | 49.975 | 2773.831 |
| `binary_search` | 27.339 | 22.244 | **20.582** | 83.291 | 4584.972 |
| `sort_window` | **29.942** | 29.976 | 30.606 | 133.875 | 7314.677 |
| `bloom_filter` | 12.332 | **12.077** | 12.258 | 1914.311 | 4931.065 |
| `hash_join` | **18.672** | 19.499 | 19.630 | 2314.606 | 5298.967 |
| `sieve` | 33.290 | 33.026 | **32.447** | 67.830 | 1954.598 |
| `fib` | **17.347** | 20.323 | 17.506 | 83.549 | 667.814 |
| `collatz` | **11.248** | 11.364 | 12.126 | 43.474 | 422.991 |
| `matmul` | 15.292 | 15.137 | **14.963** | 56.025 | 1904.794 |
| `json_parse` | **5.555** | 5.894 | 6.982 | 23.481 | 24.792 |
| `nbody` | 16.340 | 22.752 | **16.265** | 62.824 | 1643.612 |

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
| _(floor: empty program)_ | _2.083_ | _66.497_ | _**68.580**_ | _42.243_ | _53.245_ | _45.509_ |
| `lcg` | 2.239 | 78.099 | **80.338** | 43.361 | 65.956 | 54.738 |
| `packet_classifier` | 2.202 | 78.421 | **80.623** | 42.741 | 61.625 | 49.191 |
| `ring_write` | 2.330 | 75.087 | **77.417** | 41.298 | 60.707 | 50.607 |
| `histogram_bins` | 2.281 | 76.612 | **78.893** | 39.860 | 70.504 | 54.546 |
| `prefix_scan` | 2.364 | 74.256 | **76.620** | 40.581 | 65.413 | 53.089 |
| `binary_search` | 2.474 | 75.091 | **77.565** | 41.471 | 60.345 | 52.343 |
| `sort_window` | 2.471 | 74.310 | **76.781** | 40.086 | 65.874 | 57.132 |
| `bloom_filter` | 2.768 | 84.565 | **87.333** | 45.846 | 74.047 | 59.388 |
| `hash_join` | 4.383 | 165.897 | **170.280** | 45.558 | 140.164 | 88.597 |
| `sieve` | 2.443 | 74.080 | **76.523** | 41.971 | 67.602 | 59.787 |
| `fib` | 2.233 | 71.310 | **73.543** | 40.151 | 56.691 | 45.829 |
| `collatz` | 2.238 | 73.590 | **75.828** | 40.803 | 59.892 | 50.521 |
| `matmul` | 2.538 | 73.793 | **76.331** | 39.872 | 68.166 | 69.336 |
| `json_parse` | 37.414 | 293.868 | **331.282** | 79.668 | 106.168 | 132.818 |
| `nbody` | 3.346 | 83.245 | **86.591** | 41.445 | 80.771 | 73.290 |

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
