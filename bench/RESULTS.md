# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-23T16:19:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `852b2083736f8653623ac72be689366f2015088c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32651042754 |
| NURL | `v0.50.0` |
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
| _(floor: empty program)_ | _1.612_ | _1.538_ | _1.845_ | _25.691_ | _20.037_ |
| `lcg` | **39.357** | 39.365 | 39.510 | 2072.312 | 5257.468 |
| `packet_classifier` | 56.553 | **56.433** | 56.657 | 163.658 | 4482.734 |
| `ring_write` | **42.493** | 42.631 | 42.884 | 70.667 | 6255.683 |
| `histogram_bins` | **39.830** | 40.983 | 40.070 | 68.864 | 6080.405 |
| `prefix_scan` | **22.092** | 22.144 | 22.207 | 68.724 | 4678.431 |
| `binary_search` | **36.545** | 38.546 | 37.429 | 109.892 | 6132.326 |
| `sort_window` | **26.805** | 26.880 | 27.181 | 200.437 | 11313.540 |
| `bloom_filter` | 18.243 | **18.138** | 18.796 | 2878.504 | 7913.182 |
| `hash_join` | **27.315** | 28.297 | 29.704 | 3506.223 | 8369.951 |
| `sieve` | 19.065 | **18.810** | 19.196 | 68.411 | 3240.079 |
| `fib` | **25.549** | 30.083 | 25.799 | 133.344 | 1381.341 |
| `collatz` | **12.541** | 12.581 | 12.777 | 53.195 | 713.054 |
| `matmul` | **33.809** | 33.861 | 34.182 | 79.091 | 3236.727 |
| `json_parse` | 9.393 | **8.926** | 11.974 | 39.503 | 41.057 |
| `nbody` | 25.895 | 40.130 | **24.460** | 105.795 | 3041.360 |

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
| _(floor: empty program)_ | _2.860_ | _103.310_ | _**106.170**_ | _64.193_ | _91.562_ | _60.634_ |
| `lcg` | 3.093 | 105.423 | **108.516** | 64.049 | 99.646 | 66.700 |
| `packet_classifier` | 3.127 | 106.491 | **109.618** | 63.810 | 103.641 | 65.998 |
| `ring_write` | 3.285 | 108.989 | **112.274** | 66.201 | 103.274 | 67.202 |
| `histogram_bins` | 3.451 | 127.281 | **130.732** | 66.333 | 119.590 | 76.018 |
| `prefix_scan` | 3.380 | 109.709 | **113.089** | 65.530 | 108.827 | 71.248 |
| `binary_search` | 3.543 | 115.843 | **119.386** | 64.981 | 103.785 | 72.353 |
| `sort_window` | 3.721 | 117.884 | **121.605** | 65.614 | 114.712 | 78.343 |
| `bloom_filter` | 3.834 | 113.654 | **117.488** | 65.516 | 112.066 | 72.927 |
| `hash_join` | 6.452 | 275.901 | **282.353** | 70.126 | 233.082 | 123.497 |
| `sieve` | 3.417 | 108.087 | **111.504** | 64.791 | 115.031 | 78.553 |
| `fib` | 3.027 | 105.943 | **108.970** | 64.115 | 100.662 | 62.934 |
| `collatz` | 3.282 | 109.710 | **112.992** | 64.981 | 102.806 | 69.098 |
| `matmul` | 3.681 | 111.466 | **115.147** | 65.009 | 116.373 | 91.227 |
| `json_parse` | 53.729 | 458.709 | **512.438** | 117.648 | 175.505 | 181.296 |
| `nbody` | 4.979 | 136.320 | **141.299** | 66.120 | 138.418 | 100.832 |

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
