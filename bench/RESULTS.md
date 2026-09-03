# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-03T13:50:19Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16377732 KiB |
| Commit | `b4710dd4acc3f455ead9e06658aa270ffc890bda` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33762976361 |
| NURL | `v0.59.0-6-gb4710dd4` |
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
| _(floor: empty program)_ | _1.230_ | _1.193_ | _1.387_ | _18.390_ | _14.032_ |
| `lcg` | 34.151 | **34.142** | 34.347 | 1407.139 | 4271.306 |
| `packet_classifier` | **49.195** | 49.222 | 49.358 | 122.400 | 3622.751 |
| `ring_write` | 36.901 | **36.857** | 37.084 | 56.620 | 5094.086 |
| `histogram_bins` | **34.618** | 34.647 | 34.850 | 59.881 | 4796.299 |
| `prefix_scan` | **18.893** | 18.899 | 19.083 | 56.009 | 3725.862 |
| `binary_search` | 32.159 | **27.606** | 28.346 | 89.148 | 5115.963 |
| `sort_window` | **23.266** | 23.335 | 23.455 | 129.397 | 8990.819 |
| `bloom_filter` | 15.292 | **14.464** | 15.982 | 2132.407 | 6085.053 |
| `hash_join` | **21.417** | 22.163 | 23.319 | 2685.276 | 6339.231 |
| `sieve` | 15.782 | **15.738** | 15.768 | 55.615 | 2873.182 |
| `fib` | **21.676** | 25.651 | 21.809 | 111.003 | 998.908 |
| `collatz` | 10.581 | **10.547** | 10.739 | 41.265 | 582.273 |
| `matmul` | **35.000** | 35.617 | 35.662 | 64.314 | 2652.825 |
| `json_parse` | **6.888** | 6.973 | 9.437 | 29.774 | 29.245 |
| `nbody` | 20.742 | 34.846 | **20.379** | 75.325 | 2539.077 |

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
| _(floor: empty program)_ | _2.341_ | _86.194_ | _**88.535**_ | _52.247_ | _70.396_ | _46.199_ |
| `lcg` | 2.456 | 92.211 | **94.667** | 51.497 | 77.640 | 51.675 |
| `packet_classifier` | 2.530 | 93.483 | **96.013** | 52.568 | 80.028 | 51.002 |
| `ring_write` | 2.646 | 93.845 | **96.491** | 52.018 | 80.045 | 52.864 |
| `histogram_bins` | 2.658 | 100.269 | **102.927** | 52.319 | 92.280 | 58.905 |
| `prefix_scan` | 2.700 | 95.166 | **97.866** | 53.892 | 86.683 | 55.068 |
| `binary_search` | 2.818 | 93.992 | **96.810** | 53.177 | 82.773 | 56.620 |
| `sort_window` | 2.829 | 96.249 | **99.078** | 53.070 | 88.334 | 59.589 |
| `bloom_filter` | 3.120 | 96.300 | **99.420** | 52.417 | 88.309 | 56.894 |
| `hash_join` | 5.053 | 201.169 | **206.222** | 54.618 | 170.386 | 93.783 |
| `sieve` | 2.702 | 92.918 | **95.620** | 52.624 | 92.244 | 60.704 |
| `fib` | 2.498 | 94.003 | **96.501** | 53.320 | 79.280 | 50.434 |
| `collatz` | 2.609 | 94.401 | **97.010** | 52.366 | 81.109 | 53.688 |
| `matmul` | 2.983 | 94.241 | **97.224** | 52.376 | 89.445 | 69.609 |
| `json_parse` | 43.476 | 344.568 | **388.044** | 93.561 | 130.711 | 135.079 |
| `nbody` | 3.971 | 108.062 | **112.033** | 55.208 | 105.654 | 77.532 |

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
