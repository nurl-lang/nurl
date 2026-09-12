# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-12T22:41:24Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `c4d37e05b447553a9ec5bba3557eebae02816d9c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34723251497 |
| NURL | `v0.64.0` |
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
| _(floor: empty program)_ | _1.094_ | _1.094_ | _1.249_ | _18.573_ | _14.056_ |
| `lcg` | 35.124 | **34.976** | 35.051 | 1380.421 | 3748.882 |
| `packet_classifier` | 60.146 | **59.715** | 59.778 | 145.078 | 3078.913 |
| `ring_write` | 39.010 | 39.393 | **38.966** | 55.834 | 4666.798 |
| `histogram_bins` | 36.152 | **36.054** | 36.673 | 59.613 | 4436.872 |
| `prefix_scan` | 19.402 | **19.397** | 19.589 | 57.255 | 3251.244 |
| `binary_search` | 34.249 | 27.572 | **26.463** | 96.190 | 4849.064 |
| `sort_window` | **34.426** | 34.700 | 35.329 | 156.321 | 8259.549 |
| `bloom_filter` | **12.254** | **12.254** | 12.537 | 2147.985 | 5568.093 |
| `hash_join` | **20.611** | 21.829 | 22.080 | 2674.142 | 6133.923 |
| `sieve` | 33.071 | **32.532** | 32.593 | 74.250 | 2364.106 |
| `fib` | 25.954 | 26.583 | **24.887** | 97.518 | 783.287 |
| `collatz` | 13.142 | **13.133** | 13.779 | 51.281 | 493.575 |
| `matmul` | **17.523** | 17.599 | 17.692 | 62.467 | 2362.958 |
| `json_parse` | 7.624 | **6.445** | 8.116 | 27.637 | 28.614 |
| `nbody` | **19.242** | 27.351 | 19.297 | 68.939 | 1918.209 |

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
| _(floor: empty program)_ | _2.313_ | _65.433_ | _**67.746**_ | _39.051_ | _50.773_ | _50.136_ |
| `lcg` | 2.445 | 73.823 | **76.268** | 40.181 | 54.586 | 53.072 |
| `packet_classifier` | 2.720 | 74.384 | **77.104** | 40.012 | 56.195 | 56.826 |
| `ring_write` | 2.937 | 75.982 | **78.919** | 41.987 | 57.407 | 57.889 |
| `histogram_bins` | 3.069 | 84.824 | **87.893** | 40.972 | 73.034 | 62.982 |
| `prefix_scan` | 2.979 | 75.870 | **78.849** | 41.174 | 63.139 | 57.600 |
| `binary_search` | 3.155 | 73.474 | **76.629** | 40.342 | 59.657 | 60.768 |
| `sort_window` | 3.409 | 81.116 | **84.525** | 42.255 | 66.923 | 64.816 |
| `bloom_filter` | 3.759 | 76.574 | **80.333** | 41.410 | 68.191 | 59.467 |
| `hash_join` | 6.921 | 180.717 | **187.638** | 44.649 | 147.790 | 99.451 |
| `sieve` | 2.958 | 75.853 | **78.811** | 41.308 | 65.601 | 64.595 |
| `fib` | 2.596 | 74.947 | **77.543** | 40.281 | 55.489 | 52.920 |
| `collatz` | 2.800 | 76.208 | **79.008** | 40.476 | 57.977 | 53.944 |
| `matmul` | 3.511 | 74.691 | **78.202** | 41.212 | 67.579 | 75.934 |
| `json_parse` | 80.290 | 351.134 | **431.424** | 122.229 | 108.940 | 152.501 |
| `nbody` | 4.858 | 89.972 | **94.830** | 42.738 | 84.531 | 84.055 |

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
