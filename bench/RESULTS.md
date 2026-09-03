# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-03T05:25:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `62f8f6423633c1987303e5466b14d4941c0f3f51` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33718468533 |
| NURL | `v0.59.0` |
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
| _(floor: empty program)_ | _1.467_ | _1.429_ | _1.641_ | _23.395_ | _17.553_ |
| `lcg` | 39.049 | **38.998** | 39.220 | 2052.093 | 5141.146 |
| `packet_classifier` | **56.106** | 56.108 | 56.306 | 163.168 | 4265.667 |
| `ring_write` | **42.100** | 42.108 | 42.304 | 64.930 | 6365.130 |
| `histogram_bins` | **39.455** | 40.538 | 39.546 | 65.792 | 5909.264 |
| `prefix_scan` | 21.653 | **21.618** | 21.769 | 65.265 | 4765.430 |
| `binary_search` | 39.285 | 38.197 | **37.057** | 105.428 | 6507.413 |
| `sort_window` | 26.500 | **26.453** | 26.691 | 195.631 | 11157.442 |
| `bloom_filter` | 17.871 | **17.844** | 18.248 | 2886.428 | 7396.759 |
| `hash_join` | **27.084** | 27.949 | 29.381 | 3416.689 | 8210.703 |
| `sieve` | 18.095 | 18.123 | **17.891** | 65.696 | 3240.466 |
| `fib` | **24.970** | 29.698 | 25.153 | 129.887 | 1350.717 |
| `collatz` | 12.203 | **12.084** | 12.355 | 49.636 | 715.973 |
| `matmul` | 33.436 | **33.315** | 33.447 | 75.369 | 3216.547 |
| `json_parse` | 9.035 | **8.549** | 11.531 | 34.621 | 36.765 |
| `nbody` | 25.057 | 39.593 | **24.163** | 102.151 | 3023.167 |

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
| _(floor: empty program)_ | _2.655_ | _94.889_ | _**97.544**_ | _58.448_ | _76.788_ | _60.561_ |
| `lcg` | 2.774 | 105.646 | **108.420** | 57.382 | 86.677 | 69.044 |
| `packet_classifier` | 2.881 | 103.590 | **106.471** | 57.320 | 87.260 | 69.006 |
| `ring_write` | 3.026 | 105.943 | **108.969** | 58.059 | 89.587 | 71.782 |
| `histogram_bins` | 3.108 | 114.452 | **117.560** | 57.703 | 105.413 | 78.622 |
| `prefix_scan` | 3.105 | 106.815 | **109.920** | 58.170 | 94.298 | 72.556 |
| `binary_search` | 3.263 | 105.575 | **108.838** | 57.984 | 90.424 | 75.145 |
| `sort_window` | 3.328 | 109.841 | **113.169** | 59.101 | 100.409 | 79.845 |
| `bloom_filter` | 3.599 | 110.443 | **114.042** | 59.203 | 98.989 | 75.785 |
| `hash_join` | 6.122 | 255.791 | **261.913** | 61.392 | 215.071 | 129.244 |
| `sieve` | 3.176 | 107.066 | **110.242** | 58.014 | 101.150 | 78.412 |
| `fib` | 2.828 | 106.304 | **109.132** | 58.314 | 86.791 | 67.853 |
| `collatz` | 3.042 | 107.973 | **111.015** | 58.698 | 88.615 | 71.543 |
| `matmul` | 3.357 | 107.269 | **110.626** | 58.015 | 104.369 | 93.487 |
| `json_parse` | 57.043 | 454.001 | **511.044** | 113.910 | 158.089 | 174.667 |
| `nbody` | 4.745 | 124.227 | **128.972** | 59.399 | 124.779 | 102.094 |

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
