# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-23T14:10:45Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `b015cf7293cd86bf1fcd6305d94d0d57abc7a7b7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32644432199 |
| NURL | `v0.49.0-11-gb015cf72` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
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
| _(floor: empty program)_ | _1.050_ | _1.041_ | _1.159_ | _17.664_ | _11.364_ |
| `lcg` | 30.225 | **29.998** | 30.117 | 1067.066 | 3257.022 |
| `packet_classifier` | 59.075 | 59.043 | **55.538** | 130.402 | 2716.167 |
| `ring_write` | 32.796 | 33.169 | **32.746** | 50.464 | 3780.975 |
| `histogram_bins` | 31.285 | **31.130** | 31.239 | 52.385 | 3530.033 |
| `prefix_scan` | 16.553 | **16.529** | 16.896 | 49.040 | 2670.962 |
| `binary_search` | **19.723** | 21.952 | 20.763 | 81.822 | 4131.359 |
| `sort_window` | **29.937** | 29.940 | 30.644 | 136.234 | 7050.788 |
| `bloom_filter` | **10.649** | 10.724 | 10.866 | 1866.333 | 4655.101 |
| `hash_join` | **17.967** | 18.973 | 19.206 | 2261.388 | 5164.645 |
| `sieve` | **33.120** | 33.412 | 33.531 | 72.010 | 1937.195 |
| `fib` | **17.453** | 20.446 | 17.662 | 86.440 | 666.144 |
| `collatz` | **12.211** | 12.603 | 14.225 | 53.606 | 421.921 |
| `matmul` | **15.184** | 15.263 | 15.419 | 55.543 | 1871.167 |
| `json_parse` | **6.351** | 6.734 | 8.227 | 27.587 | 24.328 |
| `nbody` | **18.939** | 26.566 | 18.962 | 67.400 | 1675.833 |

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
| _(floor: empty program)_ | _2.013_ | _62.100_ | _**64.113**_ | _39.350_ | _50.580_ | _46.744_ |
| `lcg` | 2.076 | 63.273 | **65.349** | 39.394 | 60.313 | 49.239 |
| `packet_classifier` | 2.244 | 67.155 | **69.399** | 41.304 | 64.455 | 50.386 |
| `ring_write` | 2.305 | 64.564 | **66.869** | 39.938 | 63.072 | 51.969 |
| `histogram_bins` | 2.374 | 77.549 | **79.923** | 40.676 | 72.433 | 55.486 |
| `prefix_scan` | 2.296 | 64.891 | **67.187** | 38.698 | 63.058 | 53.685 |
| `binary_search` | 2.445 | 68.589 | **71.034** | 41.117 | 60.467 | 54.276 |
| `sort_window` | 2.756 | 80.184 | **82.940** | 45.102 | 76.620 | 65.391 |
| `bloom_filter` | 2.630 | 68.902 | **71.532** | 40.982 | 64.883 | 54.746 |
| `hash_join` | 4.206 | 165.105 | **169.311** | 43.283 | 140.695 | 91.130 |
| `sieve` | 2.397 | 70.301 | **72.698** | 43.359 | 70.635 | 59.637 |
| `fib` | 2.473 | 78.017 | **80.490** | 47.990 | 70.456 | 51.171 |
| `collatz` | 2.297 | 71.852 | **74.149** | 41.803 | 66.610 | 53.324 |
| `matmul` | 2.556 | 75.039 | **77.595** | 42.694 | 71.702 | 70.626 |
| `json_parse` | 40.161 | 318.847 | **359.008** | 87.014 | 110.897 | 148.536 |
| `nbody` | 3.344 | 87.647 | **90.991** | 43.265 | 87.315 | 86.880 |

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
