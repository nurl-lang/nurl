# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-22T21:47:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377676 KiB |
| Commit | `3140d2da9aaa9ef9c647ef08110df444b7a84507` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32600383406 |
| NURL | `v0.49.0-8-g3140d2da` |
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
| _(floor: empty program)_ | _1.437_ | _1.395_ | _1.617_ | _23.149_ | _17.305_ |
| `lcg` | **39.150** | 39.201 | 39.282 | 2055.357 | 5746.890 |
| `packet_classifier` | **56.220** | 56.230 | 56.573 | 163.074 | 4531.895 |
| `ring_write` | 42.212 | **42.156** | 42.331 | 66.591 | 6117.999 |
| `histogram_bins` | **39.617** | 40.752 | 39.836 | 66.709 | 6133.439 |
| `prefix_scan` | 21.725 | **21.706** | 21.821 | 65.861 | 4659.616 |
| `binary_search` | **36.259** | 38.134 | 37.102 | 107.641 | 6068.716 |
| `sort_window` | **26.606** | 26.610 | 26.836 | 196.885 | 11716.956 |
| `bloom_filter` | 18.037 | **17.921** | 18.476 | 2826.418 | 8217.929 |
| `hash_join` | **26.844** | 27.882 | 29.300 | 3425.271 | 8379.051 |
| `sieve` | 18.523 | **18.035** | 18.302 | 66.774 | 3421.644 |
| `fib` | **25.168** | 29.824 | 25.331 | 132.024 | 1358.049 |
| `collatz` | 12.178 | **12.151** | 12.363 | 49.255 | 712.025 |
| `matmul` | 33.667 | **33.473** | 33.861 | 77.913 | 3127.115 |
| `json_parse` | 8.810 | **8.603** | 11.579 | 35.126 | 37.863 |
| `nbody` | 25.134 | 39.750 | **24.108** | 99.799 | 3011.158 |

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
| _(floor: empty program)_ | _2.634_ | _104.861_ | _**107.495**_ | _59.249_ | _78.994_ | _55.444_ |
| `lcg` | 2.802 | 95.902 | **98.704** | 59.457 | 89.509 | 60.514 |
| `packet_classifier` | 2.826 | 96.023 | **98.849** | 59.405 | 91.532 | 59.864 |
| `ring_write` | 2.931 | 97.480 | **100.411** | 59.247 | 92.592 | 61.631 |
| `histogram_bins` | 3.008 | 116.261 | **119.269** | 59.112 | 109.479 | 68.767 |
| `prefix_scan` | 3.059 | 99.784 | **102.843** | 59.409 | 97.698 | 64.655 |
| `binary_search` | 3.233 | 105.865 | **109.098** | 59.949 | 95.615 | 67.042 |
| `sort_window` | 3.254 | 106.205 | **109.459** | 59.272 | 103.618 | 71.848 |
| `bloom_filter` | 3.510 | 103.449 | **106.959** | 60.694 | 103.635 | 67.056 |
| `hash_join` | 6.070 | 257.329 | **263.399** | 63.428 | 218.270 | 115.308 |
| `sieve` | 3.113 | 99.438 | **102.551** | 58.825 | 103.134 | 71.779 |
| `fib` | 2.814 | 95.385 | **98.199** | 59.052 | 91.481 | 59.315 |
| `collatz` | 2.975 | 98.568 | **101.543** | 59.222 | 92.547 | 62.724 |
| `matmul` | 3.364 | 101.900 | **105.264** | 59.366 | 106.671 | 83.725 |
| `json_parse` | 51.864 | 430.713 | **482.577** | 109.263 | 161.076 | 165.675 |
| `nbody` | 4.641 | 127.172 | **131.813** | 60.476 | 128.212 | 92.221 |

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
