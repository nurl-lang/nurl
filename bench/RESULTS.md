# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-06T18:34:17Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `4f82ef56eae2e9275dbe7b5e8786ffa8a0d13b42` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37511684646 |
| NURL | `v0.70.0-19-g4f82ef56` |
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
| _(floor: empty program)_ | _1.227_ | _1.215_ | _1.396_ | _18.192_ | _13.599_ |
| `lcg` | 34.114 | **34.109** | 34.337 | 1410.846 | 4062.745 |
| `packet_classifier` | **49.147** | 49.187 | 49.386 | 124.965 | 3515.720 |
| `ring_write` | 36.909 | **36.888** | 37.008 | 56.057 | 5223.719 |
| `histogram_bins` | 34.541 | **34.523** | 34.660 | 57.487 | 4755.251 |
| `prefix_scan` | 18.918 | **18.892** | 19.068 | 56.122 | 3712.104 |
| `binary_search` | 31.998 | **27.581** | 33.602 | 86.764 | 5085.191 |
| `sort_window` | 23.206 | **23.186** | 23.438 | 129.379 | 10576.563 |
| `bloom_filter` | **13.417** | 14.490 | 16.009 | 2186.478 | 6476.150 |
| `hash_join` | **21.369** | 22.254 | 23.356 | 2746.863 | 6397.040 |
| `sieve` | 16.222 | **15.620** | 16.074 | 56.192 | 2623.054 |
| `fib` | **21.608** | 25.636 | 25.850 | 111.963 | 999.322 |
| `collatz` | 10.579 | **10.564** | 10.769 | 39.555 | 582.510 |
| `matmul` | **35.536** | 35.605 | 36.431 | 63.987 | 2602.211 |
| `json_parse` | **6.360** | 6.818 | 9.352 | 29.359 | 30.083 |
| `nbody` | **20.785** | 34.893 | 20.861 | 76.966 | 2786.168 |

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
| _(floor: empty program)_ | _3.122_ | _86.118_ | _**89.240**_ | _53.300_ | _69.952_ | _51.571_ |
| `lcg` | 3.181 | 92.942 | **96.123** | 52.802 | 77.307 | 56.243 |
| `packet_classifier` | 3.276 | 93.392 | **96.668** | 52.986 | 77.796 | 56.995 |
| `ring_write` | 3.372 | 95.025 | **98.397** | 53.794 | 79.910 | 59.139 |
| `histogram_bins` | 3.551 | 102.261 | **105.812** | 53.641 | 92.288 | 63.838 |
| `prefix_scan` | 3.611 | 96.019 | **99.630** | 53.598 | 83.348 | 61.061 |
| `binary_search` | 3.841 | 96.390 | **100.231** | 53.887 | 82.853 | 63.250 |
| `sort_window` | 3.971 | 97.173 | **101.144** | 53.983 | 87.739 | 66.851 |
| `bloom_filter` | 4.371 | 100.308 | **104.679** | 57.060 | 90.620 | 65.779 |
| `hash_join` | 7.769 | 204.131 | **211.900** | 57.146 | 170.499 | 102.548 |
| `sieve` | 3.562 | 95.410 | **98.972** | 54.289 | 87.271 | 65.719 |
| `fib` | 3.290 | 92.823 | **96.113** | 52.969 | 77.195 | 57.451 |
| `collatz` | 3.559 | 95.782 | **99.341** | 54.019 | 79.385 | 59.127 |
| `matmul` | 4.072 | 97.879 | **101.951** | 55.377 | 89.037 | 74.750 |
| `json_parse` | 39.017 | 341.864 | **380.881** | 89.658 | 129.410 | 137.327 |
| `nbody` | 5.988 | 113.173 | **119.161** | 59.698 | 106.726 | 91.770 |

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
