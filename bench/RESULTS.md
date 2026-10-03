# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-03T10:26:10Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ea430f8061fc43ba89eafd6746f688732cd2a4f4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37116161193 |
| NURL | `v0.68.0-15-gea430f80` |
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
| _(floor: empty program)_ | _1.233_ | _1.183_ | _1.424_ | _18.742_ | _13.629_ |
| `lcg` | 34.199 | **34.117** | 34.309 | 1408.090 | 4224.278 |
| `packet_classifier` | **49.207** | 49.300 | 49.331 | 122.845 | 3522.226 |
| `ring_write` | 36.916 | **36.903** | 37.035 | 56.571 | 5112.553 |
| `histogram_bins` | 34.589 | **34.555** | 34.733 | 59.168 | 4841.506 |
| `prefix_scan` | 18.917 | **18.895** | 19.081 | 56.312 | 3575.588 |
| `binary_search` | 32.092 | **27.704** | 33.514 | 85.933 | 4980.615 |
| `sort_window` | **23.173** | 23.191 | 23.370 | 130.917 | 8814.768 |
| `bloom_filter` | **13.357** | 14.498 | 15.920 | 2155.822 | 6044.567 |
| `hash_join` | **21.335** | 22.102 | 23.349 | 2673.302 | 6652.948 |
| `sieve` | 16.129 | **15.487** | 15.568 | 56.260 | 2707.106 |
| `fib` | **21.617** | 25.670 | 25.837 | 111.537 | 999.463 |
| `collatz` | **10.575** | 10.581 | 10.799 | 40.229 | 586.099 |
| `matmul` | 36.015 | 35.627 | **35.467** | 65.243 | 2669.436 |
| `json_parse` | **6.517** | 6.830 | 9.355 | 29.165 | 29.935 |
| `nbody` | **20.712** | 34.770 | 20.861 | 74.341 | 2607.014 |

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
| _(floor: empty program)_ | _2.998_ | _84.734_ | _**87.732**_ | _52.608_ | _69.999_ | _45.343_ |
| `lcg` | 3.248 | 92.774 | **96.022** | 53.016 | 77.196 | 49.683 |
| `packet_classifier` | 3.219 | 96.717 | **99.936** | 53.931 | 91.568 | 49.278 |
| `ring_write` | 3.386 | 93.630 | **97.016** | 52.882 | 79.457 | 50.605 |
| `histogram_bins` | 3.445 | 99.583 | **103.028** | 53.726 | 91.141 | 55.990 |
| `prefix_scan` | 3.623 | 99.365 | **102.988** | 55.434 | 87.761 | 54.163 |
| `binary_search` | 3.661 | 94.387 | **98.048** | 53.810 | 80.024 | 54.415 |
| `sort_window` | 3.796 | 95.303 | **99.099** | 53.153 | 87.416 | 57.952 |
| `bloom_filter` | 4.220 | 95.964 | **100.184** | 53.005 | 86.200 | 55.505 |
| `hash_join` | 7.618 | 201.033 | **208.651** | 56.423 | 168.550 | 89.702 |
| `sieve` | 3.497 | 94.093 | **97.590** | 53.585 | 86.676 | 57.550 |
| `fib` | 3.219 | 92.468 | **95.687** | 52.417 | 78.320 | 48.490 |
| `collatz` | 3.385 | 94.440 | **97.825** | 53.206 | 78.780 | 50.565 |
| `matmul` | 3.848 | 95.034 | **98.882** | 53.641 | 89.761 | 65.983 |
| `json_parse` | 82.493 | 341.985 | **424.478** | 132.707 | 129.377 | 126.206 |
| `nbody` | 5.495 | 107.902 | **113.397** | 55.093 | 104.771 | 77.935 |

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
