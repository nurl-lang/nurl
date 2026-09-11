# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-11T11:26:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e6189baac69dc52cbe4062d0a671cbc6dee35f39` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34593634509 |
| NURL | `v0.63.0-26-ge6189baa` |
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
| _(floor: empty program)_ | _1.452_ | _1.426_ | _1.648_ | _23.497_ | _17.222_ |
| `lcg` | 39.315 | **39.305** | 39.376 | 2056.716 | 5693.106 |
| `packet_classifier` | **56.317** | 56.457 | 56.643 | 161.991 | 4399.005 |
| `ring_write` | 42.289 | **42.235** | 42.355 | 66.489 | 6422.966 |
| `histogram_bins` | **39.524** | 40.725 | 39.840 | 68.576 | 6218.326 |
| `prefix_scan` | **21.659** | 21.840 | 21.931 | 66.900 | 4529.857 |
| `binary_search` | 39.604 | 38.125 | **37.077** | 107.054 | 6242.821 |
| `sort_window` | 26.653 | **26.500** | 26.778 | 197.923 | 15644.615 |
| `bloom_filter` | **16.615** | 17.778 | 18.341 | 2850.740 | 7890.907 |
| `hash_join` | **27.170** | 28.129 | 29.436 | 3457.412 | 8442.724 |
| `sieve` | 18.781 | **18.299** | 18.308 | 66.455 | 3601.736 |
| `fib` | **25.222** | 29.918 | 25.337 | 131.946 | 1374.891 |
| `collatz` | 12.316 | **12.258** | 12.430 | 50.499 | 722.996 |
| `matmul` | 33.776 | **33.699** | 33.829 | 79.173 | 3165.345 |
| `json_parse` | 9.769 | **8.601** | 11.491 | 36.327 | 39.620 |
| `nbody` | 25.266 | 39.850 | **24.242** | 102.973 | 3192.003 |

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
| _(floor: empty program)_ | _3.043_ | _95.308_ | _**98.351**_ | _60.575_ | _79.972_ | _60.748_ |
| `lcg` | 3.199 | 108.270 | **111.469** | 60.185 | 90.534 | 70.385 |
| `packet_classifier` | 3.305 | 107.675 | **110.980** | 59.810 | 89.222 | 66.672 |
| `ring_write` | 3.526 | 107.258 | **110.784** | 59.699 | 91.518 | 70.413 |
| `histogram_bins` | 3.588 | 119.852 | **123.440** | 60.489 | 109.678 | 77.633 |
| `prefix_scan` | 3.670 | 111.765 | **115.435** | 60.857 | 97.196 | 72.545 |
| `binary_search` | 3.871 | 113.017 | **116.888** | 60.957 | 93.971 | 77.996 |
| `sort_window` | 4.007 | 112.360 | **116.367** | 61.062 | 104.589 | 81.626 |
| `bloom_filter` | 4.437 | 114.426 | **118.863** | 62.266 | 103.808 | 77.019 |
| `hash_join` | 8.510 | 262.709 | **271.219** | 66.870 | 219.288 | 125.819 |
| `sieve` | 3.690 | 109.215 | **112.905** | 61.297 | 104.845 | 82.751 |
| `fib` | 3.307 | 112.136 | **115.443** | 62.205 | 90.678 | 68.671 |
| `collatz` | 3.545 | 112.170 | **115.715** | 62.126 | 91.988 | 72.016 |
| `matmul` | 4.213 | 112.961 | **117.174** | 62.659 | 106.768 | 94.462 |
| `json_parse` | 95.027 | 474.433 | **569.460** | 154.322 | 164.006 | 178.513 |
| `nbody` | 6.174 | 131.357 | **137.531** | 65.191 | 130.337 | 103.697 |

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
