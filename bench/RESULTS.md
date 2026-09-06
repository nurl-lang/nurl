# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-06T06:08:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372432 KiB |
| Commit | `328325e44eedd6bbed600248c6d3f5f34845f2e6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34015535983 |
| NURL | `v0.61.0` |
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
| _(floor: empty program)_ | _1.104_ | _1.087_ | _1.212_ | _21.276_ | _15.438_ |
| `lcg` | 38.251 | 38.738 | **37.389** | 1507.052 | 4033.320 |
| `packet_classifier` | 66.261 | 66.550 | **66.114** | 160.936 | 3284.437 |
| `ring_write` | **40.942** | 41.050 | 40.972 | 59.788 | 4755.751 |
| `histogram_bins` | 37.493 | **37.072** | 37.818 | 61.440 | 4556.843 |
| `prefix_scan` | **19.889** | 20.292 | 20.492 | 60.570 | 3338.332 |
| `binary_search` | 36.169 | 29.779 | **28.457** | 103.237 | 4838.230 |
| `sort_window` | **35.775** | 37.039 | 38.182 | 166.005 | 8911.769 |
| `bloom_filter` | 13.816 | **13.034** | 13.462 | 2197.196 | 5861.060 |
| `hash_join` | **21.127** | 22.645 | 23.127 | 2764.083 | 6417.288 |
| `sieve` | **31.898** | 31.952 | 32.319 | 76.340 | 2490.204 |
| `fib` | **25.511** | 27.378 | 25.596 | 101.948 | 816.199 |
| `collatz` | **13.889** | 14.241 | 14.572 | 53.445 | 517.691 |
| `matmul` | 18.255 | **18.065** | 18.672 | 64.905 | 2305.504 |
| `json_parse` | **6.848** | 6.920 | 8.396 | 30.278 | 30.376 |
| `nbody` | 21.569 | 29.111 | **20.452** | 79.011 | 2003.489 |

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
| _(floor: empty program)_ | _29.022_ | _177.081_ | _**206.103**_ | _72.250_ | _94.141_ | _87.529_ |
| `lcg` | 2.353 | 83.530 | **85.883** | 44.900 | 64.508 | 52.101 |
| `packet_classifier` | 2.455 | 84.287 | **86.742** | 47.645 | 66.348 | 53.934 |
| `ring_write` | 2.414 | 82.486 | **84.900** | 45.083 | 65.242 | 51.709 |
| `histogram_bins` | 2.696 | 90.117 | **92.813** | 42.772 | 77.515 | 58.709 |
| `prefix_scan` | 2.608 | 80.867 | **83.475** | 41.814 | 63.536 | 54.846 |
| `binary_search` | 2.610 | 79.345 | **81.955** | 42.311 | 62.668 | 55.757 |
| `sort_window` | 2.644 | 80.432 | **83.076** | 42.319 | 72.870 | 62.151 |
| `bloom_filter` | 2.896 | 84.931 | **87.827** | 44.333 | 71.616 | 57.871 |
| `hash_join` | 5.003 | 200.085 | **205.088** | 49.039 | 159.607 | 99.394 |
| `sieve` | 2.461 | 79.441 | **81.902** | 42.675 | 71.262 | 60.997 |
| `fib` | 2.345 | 83.101 | **85.446** | 45.424 | 64.806 | 51.879 |
| `collatz` | 2.600 | 83.195 | **85.795** | 44.123 | 62.478 | 53.402 |
| `matmul` | 2.648 | 80.116 | **82.764** | 43.414 | 69.262 | 71.777 |
| `json_parse` | 49.668 | 363.138 | **412.806** | 96.428 | 121.961 | 154.993 |
| `nbody` | 3.931 | 99.471 | **103.402** | 46.386 | 92.993 | 82.543 |

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
