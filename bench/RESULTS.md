# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-04T14:31:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `6644f727f6c4749bfc1f27b38a3b44e010dc7911` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37209311674 |
| NURL | `v0.69.1-12-g6644f727` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
| Node | v22.23.3 |
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
| _(floor: empty program)_ | _1.248_ | _1.199_ | _1.363_ | _18.243_ | _13.581_ |
| `lcg` | **34.178** | 34.199 | 34.387 | 1412.375 | 4287.675 |
| `packet_classifier` | **49.263** | 49.316 | 49.429 | 124.671 | 3532.320 |
| `ring_write` | 37.000 | **36.979** | 37.129 | 58.776 | 5009.374 |
| `histogram_bins` | 34.693 | **34.653** | 34.807 | 59.719 | 4968.383 |
| `prefix_scan` | **18.923** | 18.931 | 19.250 | 56.507 | 3660.707 |
| `binary_search` | 32.091 | **27.709** | 33.656 | 86.881 | 5141.408 |
| `sort_window` | **23.267** | 23.283 | 23.396 | 129.082 | 8878.067 |
| `bloom_filter` | **13.435** | 14.523 | 16.020 | 2122.344 | 6293.303 |
| `hash_join` | **21.376** | 22.233 | 23.430 | 2705.530 | 6479.537 |
| `sieve` | 15.984 | **15.823** | 16.206 | 56.729 | 2589.513 |
| `fib` | **21.589** | 25.794 | 25.853 | 111.593 | 1008.808 |
| `collatz` | 10.668 | **10.614** | 10.910 | 42.256 | 587.332 |
| `matmul` | **35.010** | 36.147 | 36.813 | 66.714 | 2642.115 |
| `json_parse` | **6.571** | 7.055 | 9.538 | 33.494 | 32.673 |
| `nbody` | **20.822** | 34.939 | 21.134 | 78.860 | 2560.474 |

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
| _(floor: empty program)_ | _3.031_ | _84.628_ | _**87.659**_ | _52.585_ | _68.911_ | _45.095_ |
| `lcg` | 3.077 | 92.342 | **95.419** | 52.568 | 76.927 | 49.322 |
| `packet_classifier` | 3.386 | 98.062 | **101.448** | 55.269 | 81.556 | 50.664 |
| `ring_write` | 3.472 | 97.158 | **100.630** | 54.103 | 82.073 | 51.596 |
| `histogram_bins` | 3.513 | 102.110 | **105.623** | 54.569 | 93.325 | 57.540 |
| `prefix_scan` | 3.602 | 96.916 | **100.518** | 54.552 | 86.227 | 54.232 |
| `binary_search` | 3.683 | 94.709 | **98.392** | 53.608 | 80.116 | 54.257 |
| `sort_window` | 3.804 | 96.771 | **100.575** | 52.834 | 87.871 | 57.893 |
| `bloom_filter` | 4.346 | 98.491 | **102.837** | 54.466 | 88.998 | 57.713 |
| `hash_join` | 7.438 | 204.726 | **212.164** | 58.128 | 172.202 | 91.094 |
| `sieve` | 3.616 | 95.613 | **99.229** | 53.698 | 87.365 | 58.030 |
| `fib` | 3.231 | 95.547 | **98.778** | 53.435 | 79.299 | 49.377 |
| `collatz` | 3.439 | 97.217 | **100.656** | 55.226 | 82.910 | 51.108 |
| `matmul` | 4.099 | 98.491 | **102.590** | 55.067 | 91.523 | 66.219 |
| `json_parse` | 82.116 | 357.989 | **440.105** | 136.345 | 136.342 | 130.746 |
| `nbody` | 5.880 | 116.104 | **121.984** | 59.285 | 109.415 | 80.635 |

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
