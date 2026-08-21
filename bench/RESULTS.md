# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-21T04:29:06Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `29bf98c9747bacdf8976f971ded4f967b2c4bbb7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32446846711 |
| NURL | `v0.47.0-4-g29bf98c9` |
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
| _(floor: empty program)_ | _1.319_ | _1.263_ | _1.445_ | _22.199_ | _16.029_ |
| `lcg` | **40.745** | 40.861 | 41.030 | 1606.532 | 4313.107 |
| `packet_classifier` | 70.549 | **69.972** | 70.317 | 171.148 | 3548.841 |
| `ring_write` | 44.833 | **44.594** | 45.139 | 67.735 | 5064.895 |
| `histogram_bins` | 41.848 | **41.754** | 41.928 | 69.376 | 4830.630 |
| `prefix_scan` | 22.571 | **22.336** | 22.976 | 68.166 | 3709.797 |
| `binary_search` | **26.914** | 31.704 | 31.036 | 111.549 | 5202.642 |
| `sort_window` | **40.023** | 40.178 | 41.219 | 182.239 | 9574.191 |
| `bloom_filter` | 14.413 | **14.385** | 14.723 | 2459.341 | 6797.637 |
| `hash_join` | **23.916** | 24.960 | 25.598 | 3079.139 | 6961.393 |
| `sieve` | 37.263 | **37.041** | 37.105 | 83.865 | 2701.343 |
| `fib` | **28.499** | 29.646 | 28.887 | 113.622 | 903.314 |
| `collatz` | **14.955** | 15.227 | 16.002 | 60.109 | 569.007 |
| `matmul` | **20.484** | 20.695 | 20.691 | 74.637 | 2941.155 |
| `json_parse` | **7.523** | 7.539 | 9.592 | 32.094 | 33.520 |
| `nbody` | 22.641 | 31.890 | **22.622** | 81.052 | 2147.778 |

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
| _(floor: empty program)_ | _2.481_ | _85.967_ | _**88.448**_ | _53.172_ | _70.511_ | _52.473_ |
| `lcg` | 2.658 | 82.380 | **85.038** | 51.429 | 76.210 | 60.596 |
| `packet_classifier` | 2.753 | 85.913 | **88.666** | 52.153 | 76.682 | 58.973 |
| `ring_write` | 2.892 | 86.253 | **89.145** | 53.003 | 78.703 | 61.129 |
| `histogram_bins` | 2.943 | 103.431 | **106.374** | 52.630 | 96.462 | 69.230 |
| `prefix_scan` | 2.934 | 87.774 | **90.708** | 51.352 | 84.781 | 65.276 |
| `binary_search` | 3.162 | 95.046 | **98.208** | 53.275 | 81.889 | 67.116 |
| `sort_window` | 3.203 | 96.087 | **99.290** | 53.646 | 89.517 | 71.579 |
| `bloom_filter` | 3.491 | 92.654 | **96.145** | 53.579 | 90.516 | 67.333 |
| `hash_join` | 5.779 | 222.195 | **227.974** | 55.968 | 185.614 | 114.159 |
| `sieve` | 3.013 | 87.448 | **90.461** | 52.170 | 86.646 | 70.504 |
| `fib` | 2.690 | 83.062 | **85.752** | 51.430 | 75.509 | 58.032 |
| `collatz` | 2.865 | 86.443 | **89.308** | 51.987 | 78.837 | 61.438 |
| `matmul` | 3.145 | 88.433 | **91.578** | 52.460 | 88.385 | 83.506 |
| `json_parse` | 50.216 | 377.420 | **427.636** | 100.596 | 137.947 | 171.127 |
| `nbody` | 4.354 | 110.235 | **114.589** | 52.715 | 109.451 | 92.154 |

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
