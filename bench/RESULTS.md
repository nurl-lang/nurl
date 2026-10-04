# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-04T15:19:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c56e0a66a5ee82e9092acaf16eef1e6af9cb92c2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37212269224 |
| NURL | `v0.70.0` |
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
| _(floor: empty program)_ | _1.220_ | _1.201_ | _1.372_ | _21.102_ | _14.203_ |
| `lcg` | 34.213 | **34.210** | 34.397 | 1418.494 | 4174.748 |
| `packet_classifier` | **49.206** | 49.253 | 49.410 | 124.994 | 3603.744 |
| `ring_write` | 37.056 | **36.959** | 37.119 | 58.331 | 4988.350 |
| `histogram_bins` | 34.718 | **34.596** | 34.804 | 59.123 | 4975.819 |
| `prefix_scan` | 18.885 | **18.877** | 19.064 | 55.736 | 3730.209 |
| `binary_search` | 32.039 | **27.671** | 33.513 | 87.988 | 5557.453 |
| `sort_window` | 23.203 | **23.186** | 23.334 | 128.683 | 9699.640 |
| `bloom_filter` | **13.372** | 14.496 | 16.022 | 2179.224 | 6152.325 |
| `hash_join` | **21.411** | 22.180 | 23.297 | 2664.476 | 7332.373 |
| `sieve` | 15.785 | **15.629** | 15.652 | 55.960 | 2616.888 |
| `fib` | **21.512** | 25.652 | 25.812 | 110.019 | 999.308 |
| `collatz` | 10.610 | **10.551** | 10.792 | 38.831 | 588.191 |
| `matmul` | **35.087** | 36.084 | 35.521 | 64.803 | 2521.789 |
| `json_parse` | **6.520** | 6.815 | 9.346 | 28.939 | 29.834 |
| `nbody` | **20.683** | 34.847 | 20.757 | 75.864 | 2555.103 |

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
| _(floor: empty program)_ | _3.040_ | _88.608_ | _**91.648**_ | _54.874_ | _72.852_ | _45.695_ |
| `lcg` | 3.123 | 97.086 | **100.209** | 54.978 | 82.138 | 50.619 |
| `packet_classifier` | 3.317 | 97.446 | **100.763** | 54.904 | 82.350 | 50.710 |
| `ring_write` | 3.426 | 98.059 | **101.485** | 55.567 | 83.652 | 51.180 |
| `histogram_bins` | 3.462 | 103.656 | **107.118** | 55.106 | 96.827 | 57.436 |
| `prefix_scan` | 3.522 | 98.203 | **101.725** | 54.610 | 86.792 | 53.672 |
| `binary_search` | 3.646 | 94.420 | **98.066** | 53.170 | 81.079 | 54.489 |
| `sort_window` | 3.748 | 100.910 | **104.658** | 55.347 | 91.792 | 58.245 |
| `bloom_filter` | 4.165 | 96.488 | **100.653** | 52.855 | 85.539 | 54.560 |
| `hash_join` | 7.405 | 200.483 | **207.888** | 56.368 | 169.674 | 89.989 |
| `sieve` | 3.450 | 93.243 | **96.693** | 52.454 | 86.072 | 56.714 |
| `fib` | 3.131 | 92.144 | **95.275** | 52.243 | 76.958 | 48.507 |
| `collatz` | 3.415 | 94.086 | **97.501** | 52.251 | 78.441 | 51.250 |
| `matmul` | 3.929 | 93.880 | **97.809** | 53.306 | 88.511 | 64.664 |
| `json_parse` | 80.079 | 344.917 | **424.996** | 129.984 | 128.085 | 125.825 |
| `nbody` | 5.576 | 106.469 | **112.045** | 54.628 | 104.291 | 77.260 |

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
