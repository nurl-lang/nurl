# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-08T03:58:45Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `20b76fd965c43bccd0d45ca27cf1bbf258404e0b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37724914308 |
| NURL | `v0.71.0` |
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
| _(floor: empty program)_ | _1.227_ | _1.192_ | _1.390_ | _18.735_ | _13.694_ |
| `lcg` | 34.137 | **34.092** | 34.282 | 1407.727 | 4118.502 |
| `packet_classifier` | 49.190 | **49.136** | 49.364 | 123.969 | 3548.503 |
| `ring_write` | 36.874 | **36.867** | 36.997 | 57.156 | 4965.320 |
| `histogram_bins` | 34.521 | **34.511** | 34.654 | 58.513 | 4733.646 |
| `prefix_scan` | **18.877** | 18.980 | 19.068 | 55.126 | 3746.805 |
| `binary_search` | 32.252 | **27.634** | 33.470 | 86.860 | 4907.641 |
| `sort_window` | 23.236 | **23.189** | 23.365 | 129.990 | 8630.860 |
| `bloom_filter` | **13.389** | 14.409 | 15.933 | 2194.134 | 6072.163 |
| `hash_join` | **21.511** | 22.183 | 23.366 | 2707.849 | 6512.212 |
| `sieve` | 15.926 | **15.571** | 15.863 | 56.321 | 2816.349 |
| `fib` | **21.573** | 25.756 | 25.806 | 111.728 | 997.659 |
| `collatz` | 10.579 | **10.534** | 10.752 | 41.387 | 584.808 |
| `matmul` | **35.114** | 35.306 | 36.351 | 66.022 | 2837.737 |
| `json_parse` | **6.275** | 6.854 | 9.483 | 30.558 | 30.820 |
| `nbody` | **20.735** | 34.841 | 20.819 | 74.475 | 2517.631 |

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
| _(floor: empty program)_ | _3.058_ | _84.169_ | _**87.227**_ | _51.741_ | _68.879_ | _51.162_ |
| `lcg` | 3.178 | 93.470 | **96.648** | 52.409 | 76.016 | 56.872 |
| `packet_classifier` | 3.341 | 94.096 | **97.437** | 52.825 | 78.693 | 58.114 |
| `ring_write` | 3.489 | 95.322 | **98.811** | 53.339 | 78.975 | 59.076 |
| `histogram_bins` | 3.549 | 102.194 | **105.743** | 52.887 | 91.663 | 64.870 |
| `prefix_scan` | 3.636 | 96.478 | **100.114** | 53.167 | 82.203 | 61.390 |
| `binary_search` | 3.731 | 96.271 | **100.002** | 53.304 | 80.886 | 62.561 |
| `sort_window` | 3.918 | 98.075 | **101.993** | 53.525 | 87.268 | 66.307 |
| `bloom_filter` | 4.329 | 101.200 | **105.529** | 55.353 | 87.831 | 64.207 |
| `hash_join` | 7.083 | 204.642 | **211.725** | 56.880 | 171.074 | 99.845 |
| `sieve` | 3.808 | 97.340 | **101.148** | 53.902 | 88.229 | 68.818 |
| `fib` | 3.426 | 97.915 | **101.341** | 54.796 | 79.208 | 60.554 |
| `collatz` | 3.493 | 98.551 | **102.044** | 54.279 | 79.623 | 59.246 |
| `matmul` | 4.788 | 100.440 | **105.228** | 57.562 | 93.163 | 76.406 |
| `json_parse` | 36.652 | 362.017 | **398.669** | 88.353 | 132.348 | 138.679 |
| `nbody` | 5.669 | 113.419 | **119.088** | 57.222 | 106.278 | 89.743 |

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
