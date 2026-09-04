# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-04T03:05:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `d8cb8b3c5f849c3626d6c840fe75093aec8af4b7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33831686801 |
| NURL | `v0.59.0-12-gd8cb8b3c` |
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
| _(floor: empty program)_ | _1.199_ | _1.213_ | _1.389_ | _20.174_ | _13.772_ |
| `lcg` | 34.214 | **34.121** | 34.303 | 1409.063 | 4255.346 |
| `packet_classifier` | **49.245** | 49.288 | 49.377 | 124.709 | 3497.494 |
| `ring_write` | **36.880** | 36.928 | 37.105 | 57.552 | 5033.611 |
| `histogram_bins` | 34.578 | **34.512** | 34.813 | 58.271 | 4831.588 |
| `prefix_scan` | 18.935 | **18.893** | 19.119 | 55.998 | 3573.382 |
| `binary_search` | 32.192 | **27.689** | 28.323 | 87.991 | 4893.991 |
| `sort_window` | 23.243 | **23.211** | 23.382 | 131.133 | 8763.859 |
| `bloom_filter` | 15.267 | **14.481** | 15.994 | 2142.662 | 6339.332 |
| `hash_join` | **21.448** | 22.189 | 23.337 | 2728.882 | 6462.434 |
| `sieve` | 15.884 | **15.726** | 15.807 | 55.668 | 3200.450 |
| `fib` | **21.655** | 25.667 | 21.765 | 111.752 | 1001.631 |
| `collatz` | 10.606 | **10.529** | 10.756 | 40.694 | 584.138 |
| `matmul` | 35.403 | 35.695 | **35.283** | 65.750 | 2868.561 |
| `json_parse` | **6.828** | 7.023 | 9.407 | 29.937 | 29.252 |
| `nbody` | 20.740 | 34.858 | **20.340** | 76.756 | 2432.905 |

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
| _(floor: empty program)_ | _2.333_ | _82.545_ | _**84.878**_ | _51.303_ | _70.245_ | _48.031_ |
| `lcg` | 2.461 | 90.450 | **92.911** | 51.224 | 77.895 | 51.529 |
| `packet_classifier` | 2.510 | 92.098 | **94.608** | 51.691 | 78.799 | 51.621 |
| `ring_write` | 2.599 | 92.107 | **94.706** | 52.036 | 79.441 | 51.812 |
| `histogram_bins` | 2.678 | 100.070 | **102.748** | 52.722 | 93.324 | 58.152 |
| `prefix_scan` | 2.715 | 93.684 | **96.399** | 52.419 | 83.938 | 54.729 |
| `binary_search` | 2.831 | 93.855 | **96.686** | 52.493 | 82.404 | 56.521 |
| `sort_window` | 2.902 | 97.669 | **100.571** | 53.445 | 89.182 | 59.886 |
| `bloom_filter` | 3.100 | 95.627 | **98.727** | 53.031 | 86.704 | 56.779 |
| `hash_join` | 5.122 | 202.925 | **208.047** | 55.766 | 173.359 | 94.528 |
| `sieve` | 2.747 | 92.318 | **95.065** | 51.879 | 87.968 | 60.037 |
| `fib` | 2.520 | 92.925 | **95.445** | 52.902 | 78.883 | 50.385 |
| `collatz` | 2.658 | 97.170 | **99.828** | 54.032 | 80.755 | 53.285 |
| `matmul` | 2.940 | 93.546 | **96.486** | 52.499 | 91.024 | 70.204 |
| `json_parse` | 43.786 | 343.672 | **387.458** | 94.333 | 130.851 | 133.622 |
| `nbody` | 4.032 | 108.042 | **112.074** | 54.252 | 106.367 | 76.987 |

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
