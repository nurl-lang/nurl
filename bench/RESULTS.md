# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T21:17:02Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `785c17c7c110139631de3eed77ddf78be8aad978` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32899735011 |
| NURL | `v0.52.0-4-g785c17c7` |
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
| _(floor: empty program)_ | _1.429_ | _1.437_ | _1.670_ | _23.025_ | _17.884_ |
| `lcg` | 39.298 | **39.151** | 39.477 | 2054.755 | 5400.164 |
| `packet_classifier` | 56.477 | **56.435** | 56.570 | 163.141 | 4536.216 |
| `ring_write` | 42.246 | **42.205** | 42.327 | 66.202 | 6358.630 |
| `histogram_bins` | **39.623** | 40.721 | 39.854 | 67.615 | 5880.797 |
| `prefix_scan` | 21.671 | **21.652** | 21.779 | 67.902 | 4482.557 |
| `binary_search` | **36.250** | 38.404 | 37.313 | 106.878 | 5960.737 |
| `sort_window` | **26.614** | 26.618 | 26.793 | 197.801 | 11416.900 |
| `bloom_filter` | 17.817 | **17.776** | 18.306 | 2840.046 | 7553.086 |
| `hash_join` | **26.886** | 27.945 | 29.460 | 3415.423 | 8300.393 |
| `sieve` | 20.261 | **19.806** | 20.078 | 67.165 | 3217.218 |
| `fib` | **25.211** | 29.901 | 25.394 | 131.364 | 1345.541 |
| `collatz` | 12.310 | **12.262** | 12.528 | 51.358 | 712.433 |
| `matmul` | 33.583 | **33.482** | 33.506 | 76.081 | 3216.207 |
| `json_parse` | 8.847 | **8.545** | 11.601 | 35.422 | 37.427 |
| `nbody` | 25.115 | 39.726 | **24.040** | 101.129 | 3094.626 |

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
| _(floor: empty program)_ | _2.612_ | _95.415_ | _**98.027**_ | _59.144_ | _79.587_ | _55.480_ |
| `lcg` | 2.832 | 95.920 | **98.752** | 57.243 | 89.383 | 62.008 |
| `packet_classifier` | 2.940 | 95.997 | **98.937** | 59.099 | 90.157 | 59.822 |
| `ring_write` | 3.054 | 97.268 | **100.322** | 59.207 | 91.690 | 61.105 |
| `histogram_bins` | 3.081 | 116.780 | **119.861** | 59.321 | 108.440 | 69.127 |
| `prefix_scan` | 3.157 | 99.414 | **102.571** | 59.460 | 97.435 | 65.329 |
| `binary_search` | 3.324 | 104.014 | **107.338** | 58.351 | 93.763 | 67.726 |
| `sort_window` | 3.354 | 106.566 | **109.920** | 59.278 | 102.596 | 71.934 |
| `bloom_filter` | 3.559 | 104.021 | **107.580** | 59.705 | 101.383 | 66.626 |
| `hash_join` | 6.055 | 259.179 | **265.234** | 62.540 | 221.744 | 115.006 |
| `sieve` | 3.133 | 100.387 | **103.520** | 58.006 | 102.693 | 70.839 |
| `fib` | 2.909 | 95.916 | **98.825** | 58.962 | 89.719 | 59.301 |
| `collatz` | 3.050 | 101.514 | **104.564** | 61.585 | 93.316 | 63.411 |
| `matmul` | 3.418 | 104.828 | **108.246** | 61.210 | 110.010 | 85.890 |
| `json_parse` | 52.910 | 436.410 | **489.320** | 109.349 | 160.093 | 165.783 |
| `nbody` | 4.707 | 124.770 | **129.477** | 59.716 | 126.668 | 92.060 |

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
