# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-27T18:41:19Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `9a1ea1d4c6acdebd6be8deb2d7baae20ea87d8ea` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33104330675 |
| NURL | `v0.53.0-11-g9a1ea1d4` |
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
| _(floor: empty program)_ | _1.563_ | _1.520_ | _1.804_ | _23.948_ | _17.660_ |
| `lcg` | **43.988** | 44.059 | 44.258 | 1817.363 | 5272.010 |
| `packet_classifier` | 63.512 | **63.427** | 63.590 | 155.685 | 4704.889 |
| `ring_write` | **47.531** | 47.604 | 47.816 | 72.868 | 6665.509 |
| `histogram_bins` | **44.455** | 44.489 | 44.836 | 75.228 | 6232.652 |
| `prefix_scan` | 24.415 | **24.382** | 24.656 | 71.460 | 4718.016 |
| `binary_search` | **33.826** | 35.696 | 36.442 | 113.445 | 7401.539 |
| `sort_window` | 30.148 | **30.027** | 30.309 | 165.422 | 10997.652 |
| `bloom_filter` | 19.700 | **18.679** | 20.599 | 2760.759 | 8062.757 |
| `hash_join` | **27.591** | 28.519 | 30.088 | 3502.144 | 8362.854 |
| `sieve` | 20.367 | **20.091** | 20.182 | 71.466 | 3436.705 |
| `fib` | **27.898** | 33.157 | 28.066 | 141.794 | 1296.727 |
| `collatz` | 13.695 | **13.644** | 13.847 | 52.491 | 754.358 |
| `matmul` | **45.554** | 45.858 | 46.416 | 84.150 | 3603.392 |
| `json_parse` | **8.644** | 8.806 | 12.050 | 38.543 | 38.275 |
| `nbody` | 26.785 | 44.865 | **26.241** | 96.562 | 3250.734 |

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
| _(floor: empty program)_ | _2.949_ | _103.398_ | _**106.347**_ | _65.375_ | _87.094_ | _66.200_ |
| `lcg` | 3.086 | 102.521 | **105.607** | 63.885 | 97.366 | 74.536 |
| `packet_classifier` | 3.213 | 104.048 | **107.261** | 64.098 | 97.750 | 76.239 |
| `ring_write` | 3.338 | 105.070 | **108.408** | 65.191 | 100.064 | 75.502 |
| `histogram_bins` | 3.393 | 122.944 | **126.337** | 67.451 | 114.752 | 82.739 |
| `prefix_scan` | 3.409 | 107.250 | **110.659** | 64.287 | 103.567 | 79.854 |
| `binary_search` | 3.558 | 112.080 | **115.638** | 65.346 | 103.415 | 81.658 |
| `sort_window` | 3.594 | 115.473 | **119.067** | 65.591 | 112.227 | 87.232 |
| `bloom_filter` | 3.847 | 112.671 | **116.518** | 65.122 | 108.649 | 85.228 |
| `hash_join` | 6.416 | 254.618 | **261.034** | 66.980 | 215.501 | 130.326 |
| `sieve` | 3.422 | 105.849 | **109.271** | 64.216 | 108.576 | 85.496 |
| `fib` | 3.123 | 103.389 | **106.512** | 64.655 | 98.235 | 73.327 |
| `collatz` | 3.312 | 107.759 | **111.071** | 64.731 | 98.892 | 77.994 |
| `matmul` | 3.704 | 108.157 | **111.861** | 65.008 | 112.584 | 100.858 |
| `json_parse` | 53.005 | 416.664 | **469.669** | 115.246 | 162.883 | 184.659 |
| `nbody` | 4.936 | 133.263 | **138.199** | 66.202 | 131.849 | 108.018 |

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
