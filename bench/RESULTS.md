# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T16:14:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a7f024d8b60b664bcd35dfc5fe8b9e020343516e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32870332262 |
| NURL | `v0.51.0-19-ga7f024d8` |
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
| _(floor: empty program)_ | _1.259_ | _1.268_ | _1.406_ | _20.801_ | _14.990_ |
| `lcg` | **34.183** | 34.317 | 34.463 | 1418.528 | 4093.013 |
| `packet_classifier` | 49.433 | **49.307** | 50.012 | 121.892 | 3625.083 |
| `ring_write` | 37.100 | **36.993** | 37.231 | 58.574 | 5063.527 |
| `histogram_bins` | 34.630 | **34.588** | 34.774 | 60.036 | 4766.468 |
| `prefix_scan` | 19.078 | **19.035** | 19.181 | 56.342 | 3605.514 |
| `binary_search` | **26.549** | 27.728 | 28.342 | 89.717 | 5576.213 |
| `sort_window` | 23.278 | **23.237** | 23.445 | 129.260 | 9909.666 |
| `bloom_filter` | 15.275 | **14.499** | 16.027 | 2149.324 | 6148.089 |
| `hash_join` | **21.416** | 22.160 | 23.420 | 2631.933 | 6601.485 |
| `sieve` | 16.212 | **15.976** | 16.058 | 58.366 | 2690.524 |
| `fib` | **21.617** | 25.807 | 21.757 | 111.453 | 1002.667 |
| `collatz` | 10.617 | **10.578** | 10.769 | 42.873 | 592.723 |
| `matmul` | **35.251** | 36.307 | 35.701 | 66.418 | 2661.179 |
| `json_parse` | **6.846** | 7.020 | 9.429 | 31.282 | 29.796 |
| `nbody` | 20.807 | 34.882 | **20.375** | 76.746 | 2480.396 |

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
| _(floor: empty program)_ | _2.340_ | _83.775_ | _**86.115**_ | _53.073_ | _72.218_ | _64.843_ |
| `lcg` | 2.515 | 85.656 | **88.171** | 52.965 | 80.831 | 53.484 |
| `packet_classifier` | 2.558 | 86.518 | **89.076** | 53.571 | 82.007 | 53.327 |
| `ring_write` | 2.581 | 87.423 | **90.004** | 53.109 | 84.224 | 53.385 |
| `histogram_bins` | 2.683 | 101.591 | **104.274** | 54.779 | 95.124 | 59.580 |
| `prefix_scan` | 2.709 | 88.890 | **91.599** | 52.800 | 87.119 | 56.936 |
| `binary_search` | 2.824 | 92.574 | **95.398** | 53.368 | 82.999 | 57.429 |
| `sort_window` | 2.930 | 94.514 | **97.444** | 53.173 | 89.951 | 61.178 |
| `bloom_filter` | 3.068 | 91.678 | **94.746** | 53.279 | 89.576 | 58.540 |
| `hash_join` | 4.997 | 201.763 | **206.760** | 56.235 | 174.426 | 96.077 |
| `sieve` | 2.717 | 88.568 | **91.285** | 53.069 | 89.991 | 62.361 |
| `fib` | 2.526 | 84.385 | **86.911** | 52.642 | 79.763 | 51.903 |
| `collatz` | 2.662 | 88.982 | **91.644** | 54.199 | 84.135 | 54.787 |
| `matmul` | 2.932 | 92.826 | **95.758** | 53.850 | 91.316 | 72.243 |
| `json_parse` | 40.476 | 333.660 | **374.136** | 92.920 | 133.038 | 137.264 |
| `nbody` | 3.970 | 109.854 | **113.824** | 55.050 | 110.140 | 78.752 |

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
