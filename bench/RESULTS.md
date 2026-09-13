# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-13T15:48:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e79679886bf91d2d256f8b61814d5607be94f35d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34766469670 |
| NURL | `v0.65.0` |
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
| _(floor: empty program)_ | _1.434_ | _1.468_ | _1.609_ | _23.965_ | _17.704_ |
| `lcg` | **38.949** | 39.170 | 39.150 | 2044.809 | 5088.703 |
| `packet_classifier` | 56.202 | **56.052** | 56.274 | 160.730 | 5052.636 |
| `ring_write` | 42.213 | **42.167** | 42.439 | 66.415 | 6440.015 |
| `histogram_bins` | **39.525** | 40.787 | 39.942 | 67.521 | 6102.980 |
| `prefix_scan` | 21.756 | **21.672** | 21.771 | 64.833 | 4794.798 |
| `binary_search` | 39.413 | 38.203 | **36.850** | 106.277 | 5948.532 |
| `sort_window` | **26.534** | 26.561 | 26.826 | 198.674 | 11755.592 |
| `bloom_filter` | **16.474** | 17.773 | 18.275 | 2850.360 | 7724.856 |
| `hash_join` | **27.130** | 28.089 | 29.594 | 3475.226 | 8449.243 |
| `sieve` | 18.645 | **17.952** | 17.985 | 64.948 | 3325.846 |
| `fib` | **25.135** | 29.824 | 25.195 | 131.655 | 1354.977 |
| `collatz` | **12.456** | 12.731 | 12.482 | 50.247 | 714.576 |
| `matmul` | 33.401 | **33.369** | 33.647 | 75.101 | 3004.162 |
| `json_parse` | 9.750 | **8.496** | 11.503 | 34.439 | 38.157 |
| `nbody` | 25.012 | 39.600 | **24.150** | 97.500 | 3103.332 |

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
| _(floor: empty program)_ | _3.179_ | _96.372_ | _**99.551**_ | _58.977_ | _81.064_ | _60.802_ |
| `lcg` | 3.354 | 106.581 | **109.935** | 58.732 | 88.446 | 68.801 |
| `packet_classifier` | 3.494 | 102.984 | **106.478** | 57.150 | 87.200 | 65.857 |
| `ring_write` | 3.719 | 108.785 | **112.504** | 58.931 | 89.495 | 68.172 |
| `histogram_bins` | 3.797 | 113.273 | **117.070** | 57.540 | 104.808 | 76.313 |
| `prefix_scan` | 3.879 | 108.014 | **111.893** | 59.037 | 94.508 | 73.541 |
| `binary_search` | 4.211 | 109.543 | **113.754** | 59.762 | 91.263 | 81.064 |
| `sort_window` | 4.272 | 110.111 | **114.383** | 59.195 | 101.162 | 80.058 |
| `bloom_filter` | 4.678 | 112.230 | **116.908** | 60.287 | 97.787 | 73.089 |
| `hash_join` | 9.265 | 255.510 | **264.775** | 63.815 | 214.203 | 121.513 |
| `sieve` | 4.052 | 106.472 | **110.524** | 57.955 | 99.993 | 78.773 |
| `fib` | 3.348 | 103.558 | **106.906** | 57.418 | 86.190 | 65.061 |
| `collatz` | 3.754 | 107.366 | **111.120** | 58.819 | 90.750 | 70.762 |
| `matmul` | 4.402 | 105.492 | **109.894** | 59.262 | 100.814 | 106.810 |
| `json_parse` | 105.614 | 462.810 | **568.424** | 161.441 | 157.028 | 171.461 |
| `nbody` | 6.510 | 124.292 | **130.802** | 60.642 | 123.931 | 100.494 |

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
