# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-03T21:24:47Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `751d0e0aa3d85b072e142e97cd368b930c269549` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37154704809 |
| NURL | `v0.69.1-6-g751d0e0a` |
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
| _(floor: empty program)_ | _1.422_ | _1.405_ | _1.633_ | _22.625_ | _17.084_ |
| `lcg` | **39.158** | 39.223 | 39.194 | 1908.979 | 5068.504 |
| `packet_classifier` | 56.222 | **56.204** | 56.422 | 162.469 | 4357.725 |
| `ring_write` | 42.232 | **42.194** | 42.368 | 67.061 | 6382.333 |
| `histogram_bins` | **39.715** | 40.833 | 40.794 | 65.846 | 6055.733 |
| `prefix_scan` | **21.809** | 21.842 | 22.073 | 67.361 | 4736.821 |
| `binary_search` | 39.603 | **38.310** | 40.968 | 106.374 | 6209.946 |
| `sort_window` | **26.644** | 26.775 | 26.756 | 198.671 | 12127.912 |
| `bloom_filter` | **16.598** | 17.753 | 18.345 | 2836.606 | 7484.917 |
| `hash_join` | **26.845** | 27.909 | 29.171 | 3469.631 | 8476.749 |
| `sieve` | 18.890 | **18.354** | 18.367 | 68.140 | 3271.050 |
| `fib` | **25.093** | 29.730 | 30.042 | 131.547 | 1372.567 |
| `collatz` | 12.258 | **12.160** | 12.395 | 49.966 | 742.834 |
| `matmul` | 33.715 | **33.502** | 33.605 | 78.268 | 3197.964 |
| `json_parse` | 8.996 | **8.547** | 11.742 | 35.748 | 38.900 |
| `nbody` | 25.330 | 39.712 | **25.230** | 99.338 | 3100.151 |

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
| _(floor: empty program)_ | _3.548_ | _99.980_ | _**103.528**_ | _61.325_ | _79.890_ | _52.906_ |
| `lcg` | 3.630 | 109.016 | **112.646** | 59.963 | 90.729 | 58.768 |
| `packet_classifier` | 3.654 | 109.537 | **113.191** | 60.113 | 90.659 | 57.497 |
| `ring_write` | 3.937 | 110.802 | **114.739** | 60.845 | 91.290 | 60.676 |
| `histogram_bins` | 4.063 | 119.255 | **123.318** | 60.813 | 108.424 | 66.174 |
| `prefix_scan` | 4.085 | 112.148 | **116.233** | 61.431 | 97.452 | 62.530 |
| `binary_search` | 4.300 | 112.872 | **117.172** | 62.074 | 94.979 | 64.487 |
| `sort_window` | 4.511 | 115.717 | **120.228** | 61.598 | 104.385 | 70.081 |
| `bloom_filter` | 5.036 | 115.141 | **120.177** | 61.308 | 102.036 | 65.230 |
| `hash_join` | 9.202 | 260.296 | **269.498** | 65.329 | 218.737 | 109.873 |
| `sieve` | 4.113 | 112.261 | **116.374** | 61.559 | 104.079 | 67.545 |
| `fib` | 3.727 | 107.783 | **111.510** | 59.562 | 89.701 | 57.543 |
| `collatz` | 3.905 | 110.613 | **114.518** | 60.546 | 90.711 | 59.335 |
| `matmul` | 4.586 | 111.875 | **116.461** | 61.433 | 105.914 | 78.840 |
| `json_parse` | 107.238 | 457.399 | **564.637** | 164.913 | 160.367 | 155.390 |
| `nbody` | 6.699 | 130.765 | **137.464** | 63.515 | 126.997 | 94.620 |

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
