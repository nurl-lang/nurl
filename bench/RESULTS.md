# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T16:52:34Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `9cbb1e25a3c72289ca048fa889d158747c359fda` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32394015183 |
| NURL | `v0.46.0-15-g9cbb1e25` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
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
| _(floor: empty program)_ | _1.450_ | _1.448_ | _1.618_ | _23.799_ | _17.893_ |
| `lcg` | **39.010** | 39.057 | 39.293 | 2067.190 | 5352.976 |
| `packet_classifier` | 56.423 | **56.355** | 56.635 | 162.075 | 4371.427 |
| `ring_write` | **42.206** | 42.221 | 42.418 | 66.193 | 6108.757 |
| `histogram_bins` | 39.601 | 40.546 | **39.002** | 66.316 | 5971.454 |
| `prefix_scan` | **21.696** | 21.735 | 22.083 | 64.958 | 4484.773 |
| `binary_search` | **36.140** | 38.334 | 39.947 | 106.690 | 5956.210 |
| `sort_window` | **26.686** | 26.690 | 26.774 | 197.223 | 11607.105 |
| `bloom_filter` | 17.559 | **17.138** | 18.376 | 2840.198 | 7807.284 |
| `hash_join` | **27.029** | 27.954 | 29.330 | 3420.865 | 8168.884 |
| `sieve` | 18.511 | **18.203** | 20.427 | 65.659 | 3216.431 |
| `fib` | **25.217** | 29.665 | 28.128 | 131.432 | 1370.215 |
| `collatz` | 12.329 | **12.319** | 12.418 | 50.466 | 713.660 |
| `matmul` | 33.707 | **33.552** | 33.888 | 77.796 | 3524.641 |
| `json_parse` | 8.999 | **8.959** | 12.108 | 37.974 | 39.176 |
| `nbody` | 25.204 | 40.104 | **24.205** | 101.711 | 3097.435 |

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
| _(floor: empty program)_ | _2.760_ | _97.510_ | _**100.270**_ | _60.043_ | _81.526_ | _67.002_ |
| `lcg` | 2.787 | 95.228 | **98.015** | 59.510 | 91.223 | 68.221 |
| `packet_classifier` | 2.891 | 95.599 | **98.490** | 58.536 | 90.498 | 67.674 |
| `ring_write` | 3.007 | 97.872 | **100.879** | 59.833 | 93.409 | 69.421 |
| `histogram_bins` | 3.086 | 114.677 | **117.763** | 58.685 | 109.052 | 78.487 |
| `prefix_scan` | 3.109 | 102.771 | **105.880** | 61.923 | 96.787 | 74.176 |
| `binary_search` | 3.261 | 104.671 | **107.932** | 59.500 | 94.423 | 75.098 |
| `sort_window` | 3.301 | 106.318 | **109.619** | 59.242 | 102.252 | 79.674 |
| `bloom_filter` | 3.532 | 102.158 | **105.690** | 59.203 | 102.233 | 77.299 |
| `hash_join` | 6.037 | 257.996 | **264.033** | 62.425 | 219.523 | 130.578 |
| `sieve` | 3.103 | 99.173 | **102.276** | 59.947 | 103.628 | 79.595 |
| `fib` | 2.851 | 95.720 | **98.571** | 58.787 | 90.165 | 67.907 |
| `collatz` | 3.034 | 99.076 | **102.110** | 59.473 | 93.109 | 69.740 |
| `matmul` | 3.384 | 101.594 | **104.978** | 59.655 | 106.608 | 92.004 |
| `json_parse` | 53.258 | 436.528 | **489.786** | 112.202 | 162.644 | 181.913 |
| `nbody` | 4.872 | 129.590 | **134.462** | 61.933 | 128.929 | 100.525 |

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
