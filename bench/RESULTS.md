# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T05:10:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `90a31eba6ed1b8351c567027711864489c0b010a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33235364377 |
| NURL | `v0.54.0-12-g90a31eba` |
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
| _(floor: empty program)_ | _1.242_ | _1.287_ | _1.385_ | _22.492_ | _16.254_ |
| `lcg` | **40.840** | 40.845 | 41.022 | 1614.256 | 4327.623 |
| `packet_classifier` | 71.051 | 70.890 | **70.287** | 173.108 | 3614.581 |
| `ring_write` | 44.781 | **44.667** | 45.448 | 68.522 | 5273.719 |
| `histogram_bins` | 41.846 | **41.667** | 41.844 | 70.911 | 4916.225 |
| `prefix_scan` | **22.347** | 22.358 | 22.876 | 67.943 | 3801.795 |
| `binary_search` | 39.570 | 32.103 | **30.826** | 112.881 | 5387.464 |
| `sort_window` | **39.986** | 40.020 | 41.100 | 182.343 | 10043.541 |
| `bloom_filter` | **14.331** | 14.422 | 14.675 | 2469.281 | 6560.372 |
| `hash_join` | **24.012** | 25.482 | 25.757 | 3050.748 | 6980.037 |
| `sieve` | 36.480 | **36.076** | 36.249 | 84.828 | 2969.586 |
| `fib` | 28.711 | 29.994 | **28.683** | 115.919 | 904.764 |
| `collatz` | **14.928** | 15.233 | 15.993 | 60.111 | 568.359 |
| `matmul` | **19.862** | 20.566 | 20.881 | 72.556 | 2727.687 |
| `json_parse` | 7.777 | **7.447** | 9.697 | 31.764 | 32.823 |
| `nbody` | **22.438** | 31.852 | 22.507 | 85.959 | 2146.036 |

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
| _(floor: empty program)_ | _2.504_ | _83.416_ | _**85.920**_ | _51.893_ | _68.193_ | _59.139_ |
| `lcg` | 2.616 | 93.283 | **95.899** | 52.352 | 77.211 | 66.196 |
| `packet_classifier` | 2.745 | 93.916 | **96.661** | 52.866 | 78.923 | 66.789 |
| `ring_write` | 2.860 | 95.410 | **98.270** | 52.850 | 80.028 | 69.521 |
| `histogram_bins` | 2.844 | 103.154 | **105.998** | 52.422 | 94.828 | 77.693 |
| `prefix_scan` | 2.927 | 94.603 | **97.530** | 52.018 | 82.180 | 70.919 |
| `binary_search` | 3.062 | 95.900 | **98.962** | 53.690 | 81.120 | 73.654 |
| `sort_window` | 3.150 | 97.376 | **100.526** | 52.270 | 86.685 | 80.647 |
| `bloom_filter` | 3.349 | 96.637 | **99.986** | 52.426 | 86.419 | 73.612 |
| `hash_join` | 5.813 | 223.066 | **228.879** | 55.073 | 185.276 | 129.119 |
| `sieve` | 2.934 | 92.656 | **95.590** | 51.961 | 85.888 | 78.348 |
| `fib` | 2.681 | 92.398 | **95.079** | 51.360 | 75.495 | 63.923 |
| `collatz` | 2.835 | 94.055 | **96.890** | 51.168 | 76.496 | 68.485 |
| `matmul` | 3.121 | 94.244 | **97.365** | 51.311 | 88.320 | 91.576 |
| `json_parse` | 50.890 | 377.931 | **428.821** | 101.489 | 136.235 | 181.301 |
| `nbody` | 4.291 | 111.356 | **115.647** | 53.160 | 107.314 | 98.842 |

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
