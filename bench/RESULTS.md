# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-03T14:43:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `25f31efd876d43741fa7a199d19d3b7da3fad28c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37130333422 |
| NURL | `v0.69.0` |
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
| _(floor: empty program)_ | _1.433_ | _1.433_ | _1.652_ | _21.357_ | _16.852_ |
| `lcg` | **38.999** | 39.101 | 39.166 | 1901.176 | 5118.100 |
| `packet_classifier` | 56.435 | **56.109** | 56.513 | 162.009 | 4345.451 |
| `ring_write` | 42.331 | **42.316** | 42.509 | 66.758 | 6544.213 |
| `histogram_bins` | **39.625** | 40.707 | 40.830 | 67.212 | 6025.701 |
| `prefix_scan` | **21.722** | 21.792 | 21.957 | 66.458 | 4597.404 |
| `binary_search` | 39.432 | **38.455** | 41.109 | 107.306 | 6149.701 |
| `sort_window` | **26.480** | 26.549 | 26.794 | 197.712 | 12315.306 |
| `bloom_filter` | **16.562** | 17.777 | 18.289 | 2855.059 | 7511.098 |
| `hash_join` | **26.692** | 27.965 | 29.160 | 3476.179 | 8358.725 |
| `sieve` | 19.837 | 19.736 | **19.698** | 66.304 | 3293.176 |
| `fib` | **25.113** | 29.702 | 29.799 | 131.028 | 1372.963 |
| `collatz` | 12.249 | **12.135** | 12.411 | 47.666 | 733.622 |
| `matmul` | 33.792 | 34.181 | **33.457** | 75.313 | 3248.088 |
| `json_parse` | 8.944 | **8.515** | 11.951 | 34.875 | 38.670 |
| `nbody` | **25.041** | 39.662 | 25.162 | 99.487 | 3043.197 |

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
| _(floor: empty program)_ | _3.780_ | _96.231_ | _**100.011**_ | _58.808_ | _76.036_ | _52.439_ |
| `lcg` | 3.484 | 106.525 | **110.009** | 59.018 | 87.630 | 56.791 |
| `packet_classifier` | 3.693 | 109.413 | **113.106** | 60.705 | 90.039 | 56.785 |
| `ring_write` | 3.883 | 111.334 | **115.217** | 60.752 | 89.815 | 58.309 |
| `histogram_bins` | 4.005 | 118.582 | **122.587** | 60.773 | 109.636 | 66.721 |
| `prefix_scan` | 4.052 | 113.235 | **117.287** | 62.797 | 98.415 | 62.643 |
| `binary_search` | 4.292 | 111.687 | **115.979** | 61.506 | 93.847 | 63.612 |
| `sort_window` | 4.453 | 114.558 | **119.011** | 61.814 | 103.354 | 68.481 |
| `bloom_filter` | 4.964 | 114.641 | **119.605** | 61.539 | 104.294 | 66.813 |
| `hash_join` | 9.278 | 257.676 | **266.954** | 65.323 | 221.428 | 109.083 |
| `sieve` | 4.087 | 108.199 | **112.286** | 59.684 | 100.570 | 66.594 |
| `fib` | 3.599 | 106.019 | **109.618** | 58.354 | 88.113 | 56.021 |
| `collatz` | 3.837 | 109.091 | **112.928** | 58.570 | 89.805 | 58.520 |
| `matmul` | 4.566 | 109.036 | **113.602** | 60.193 | 102.706 | 77.093 |
| `json_parse` | 103.942 | 457.066 | **561.008** | 162.229 | 160.363 | 155.444 |
| `nbody` | 6.724 | 131.453 | **138.177** | 64.964 | 129.262 | 93.973 |

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
