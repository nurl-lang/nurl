# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T19:30:14Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `09a6d3bc4a094077ee66ffb496f0fa315f2a18cc` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32889437745 |
| NURL | `v0.52.0` |
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
| _(floor: empty program)_ | _1.446_ | _1.438_ | _1.666_ | _28.904_ | _19.582_ |
| `lcg` | **39.490** | 39.579 | 39.748 | 2093.124 | 5051.517 |
| `packet_classifier` | **56.228** | 56.332 | 56.585 | 162.965 | 4333.894 |
| `ring_write` | **42.301** | 42.377 | 42.558 | 67.912 | 6170.917 |
| `histogram_bins` | **39.803** | 40.881 | 40.018 | 67.786 | 5988.969 |
| `prefix_scan` | 21.799 | **21.649** | 21.760 | 65.877 | 4444.082 |
| `binary_search` | **36.465** | 38.329 | 37.489 | 107.853 | 6373.183 |
| `sort_window` | **26.616** | 26.656 | 26.792 | 197.668 | 11856.656 |
| `bloom_filter` | **17.891** | 17.959 | 18.334 | 2863.464 | 7820.531 |
| `hash_join` | **27.218** | 28.199 | 29.459 | 3442.983 | 8318.566 |
| `sieve` | 19.289 | **18.635** | 19.091 | 71.560 | 3330.817 |
| `fib` | **25.375** | 30.120 | 25.654 | 136.082 | 1364.299 |
| `collatz` | 12.663 | **12.465** | 12.975 | 53.178 | 720.405 |
| `matmul` | 39.778 | **33.626** | 33.650 | 77.401 | 3181.160 |
| `json_parse` | 9.538 | **8.872** | 11.999 | 40.497 | 39.144 |
| `nbody` | 25.228 | 39.932 | **24.087** | 103.028 | 3110.382 |

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
| _(floor: empty program)_ | _2.662_ | _90.979_ | _**93.641**_ | _57.497_ | _155.617_ | _54.574_ |
| `lcg` | 3.060 | 109.365 | **112.425** | 64.344 | 97.075 | 63.363 |
| `packet_classifier` | 2.943 | 101.802 | **104.745** | 61.933 | 118.409 | 60.809 |
| `ring_write` | 3.019 | 97.788 | **100.807** | 59.307 | 94.193 | 63.450 |
| `histogram_bins` | 3.054 | 117.153 | **120.207** | 59.722 | 110.805 | 69.962 |
| `prefix_scan` | 3.074 | 101.835 | **104.909** | 60.843 | 100.513 | 64.940 |
| `binary_search` | 3.239 | 106.557 | **109.796** | 60.165 | 97.625 | 67.684 |
| `sort_window` | 3.365 | 108.643 | **112.008** | 61.095 | 104.670 | 72.702 |
| `bloom_filter` | 3.684 | 111.770 | **115.454** | 63.952 | 113.961 | 72.661 |
| `hash_join` | 6.639 | 276.409 | **283.048** | 69.773 | 236.399 | 119.229 |
| `sieve` | 3.158 | 104.138 | **107.296** | 61.552 | 109.499 | 71.918 |
| `fib` | 3.035 | 104.272 | **107.307** | 63.902 | 98.001 | 64.919 |
| `collatz` | 3.198 | 105.144 | **108.342** | 62.961 | 95.200 | 64.469 |
| `matmul` | 3.776 | 109.642 | **113.418** | 64.583 | 113.152 | 90.215 |
| `json_parse` | 54.142 | 462.994 | **517.136** | 117.179 | 172.140 | 180.714 |
| `nbody` | 4.781 | 131.550 | **136.331** | 64.047 | 138.617 | 102.876 |

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
