# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-12T16:43:32Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373440 KiB |
| Commit | `7722670190720f79e7de8d9d25014d50863907aa` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34705897392 |
| NURL | `v0.63.0-18-g77226701` |
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
| _(floor: empty program)_ | _1.213_ | _1.209_ | _1.383_ | _18.194_ | _13.646_ |
| `lcg` | 34.137 | **34.129** | 34.324 | 1410.199 | 4145.002 |
| `packet_classifier` | **49.167** | 49.241 | 49.304 | 123.079 | 3637.127 |
| `ring_write` | 36.862 | **36.836** | 37.027 | 56.343 | 5021.577 |
| `histogram_bins` | 34.497 | **34.485** | 34.722 | 57.313 | 4836.472 |
| `prefix_scan` | **18.888** | 18.893 | 19.121 | 55.458 | 3737.534 |
| `binary_search` | 32.168 | **27.618** | 28.409 | 88.122 | 4877.715 |
| `sort_window` | **23.169** | 23.206 | 23.337 | 128.797 | 8988.188 |
| `bloom_filter` | **13.439** | 14.493 | 15.983 | 2152.914 | 5990.820 |
| `hash_join` | **21.346** | 22.144 | 23.287 | 2672.400 | 6648.784 |
| `sieve` | 15.964 | **15.589** | 15.624 | 57.393 | 2672.012 |
| `fib` | **21.570** | 25.665 | 21.716 | 110.915 | 1006.844 |
| `collatz` | 10.603 | **10.555** | 10.754 | 40.223 | 584.964 |
| `matmul` | 35.789 | **35.323** | 35.908 | 65.248 | 2787.143 |
| `json_parse` | 7.283 | **7.041** | 9.474 | 29.195 | 29.927 |
| `nbody` | 20.724 | 34.789 | **20.292** | 74.844 | 2581.422 |

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
| _(floor: empty program)_ | _2.696_ | _81.039_ | _**83.735**_ | _51.595_ | _67.345_ | _51.757_ |
| `lcg` | 2.876 | 89.150 | **92.026** | 51.217 | 75.490 | 58.217 |
| `packet_classifier` | 3.009 | 90.726 | **93.735** | 51.798 | 76.538 | 58.328 |
| `ring_write` | 3.125 | 91.162 | **94.287** | 51.968 | 77.727 | 60.097 |
| `histogram_bins` | 3.171 | 97.391 | **100.562** | 51.523 | 89.941 | 65.543 |
| `prefix_scan` | 3.211 | 92.219 | **95.430** | 51.945 | 81.619 | 61.866 |
| `binary_search` | 3.449 | 91.853 | **95.302** | 51.782 | 78.893 | 64.683 |
| `sort_window` | 3.567 | 94.005 | **97.572** | 52.531 | 86.315 | 67.501 |
| `bloom_filter` | 3.823 | 95.853 | **99.676** | 53.569 | 86.349 | 65.241 |
| `hash_join` | 7.094 | 207.349 | **214.443** | 58.713 | 171.565 | 103.219 |
| `sieve` | 3.272 | 92.164 | **95.436** | 52.909 | 86.145 | 68.265 |
| `fib` | 2.950 | 92.562 | **95.512** | 52.664 | 77.145 | 57.235 |
| `collatz` | 3.144 | 93.584 | **96.728** | 52.650 | 78.457 | 60.127 |
| `matmul` | 3.648 | 93.801 | **97.449** | 52.955 | 87.503 | 77.549 |
| `json_parse` | 73.081 | 354.364 | **427.445** | 123.121 | 127.786 | 144.199 |
| `nbody` | 5.078 | 106.057 | **111.135** | 54.717 | 107.570 | 84.905 |

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
