# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-31T22:06:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a281f597d0ef3b1402e7a22e7bf90491d61c4822` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33444271290 |
| NURL | `v0.57.0-3-ga281f597` |
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
| _(floor: empty program)_ | _1.434_ | _1.421_ | _1.611_ | _22.388_ | _17.075_ |
| `lcg` | 39.009 | **38.987** | 39.151 | 2044.828 | 5525.893 |
| `packet_classifier` | 56.078 | **56.068** | 56.266 | 161.548 | 4741.174 |
| `ring_write` | 42.176 | **42.114** | 42.304 | 65.963 | 6581.721 |
| `histogram_bins` | **39.491** | 40.521 | 39.675 | 65.221 | 6329.380 |
| `prefix_scan` | **21.607** | 21.608 | 21.739 | 65.588 | 5080.709 |
| `binary_search` | 39.406 | 38.134 | **36.839** | 105.021 | 5931.799 |
| `sort_window` | **26.477** | 26.490 | 26.767 | 197.335 | 12545.892 |
| `bloom_filter` | **17.760** | 17.807 | 18.254 | 2850.479 | 8384.406 |
| `hash_join` | **26.799** | 27.790 | 29.378 | 3404.453 | 9037.032 |
| `sieve` | 18.161 | **17.644** | 17.755 | 66.663 | 3368.494 |
| `fib` | **25.036** | 29.604 | 25.199 | 132.402 | 1351.679 |
| `collatz` | 12.194 | **12.142** | 12.318 | 48.922 | 719.369 |
| `matmul` | **33.394** | 33.403 | 33.621 | 76.324 | 3269.631 |
| `json_parse` | 8.735 | **8.535** | 11.581 | 35.211 | 37.659 |
| `nbody` | 25.352 | 39.599 | **23.936** | 101.133 | 3031.781 |

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
| _(floor: empty program)_ | _2.677_ | _92.535_ | _**95.212**_ | _59.168_ | _77.203_ | _61.290_ |
| `lcg` | 2.821 | 103.659 | **106.480** | 57.440 | 88.535 | 70.030 |
| `packet_classifier` | 2.897 | 104.653 | **107.550** | 59.388 | 88.228 | 68.957 |
| `ring_write` | 2.969 | 105.417 | **108.386** | 57.905 | 90.297 | 70.500 |
| `histogram_bins` | 3.083 | 116.442 | **119.525** | 59.767 | 115.788 | 79.913 |
| `prefix_scan` | 3.111 | 106.481 | **109.592** | 58.210 | 96.861 | 72.393 |
| `binary_search` | 3.272 | 107.494 | **110.766** | 57.994 | 92.312 | 76.107 |
| `sort_window` | 3.309 | 107.959 | **111.268** | 58.839 | 101.821 | 80.611 |
| `bloom_filter` | 3.589 | 110.005 | **113.594** | 58.660 | 101.295 | 75.540 |
| `hash_join` | 6.112 | 255.363 | **261.475** | 61.035 | 214.723 | 123.106 |
| `sieve` | 3.187 | 105.381 | **108.568** | 58.058 | 102.434 | 79.626 |
| `fib` | 2.833 | 103.777 | **106.610** | 57.843 | 88.122 | 65.804 |
| `collatz` | 3.069 | 106.737 | **109.806** | 57.704 | 90.734 | 70.179 |
| `matmul` | 3.383 | 105.897 | **109.280** | 58.318 | 105.234 | 91.594 |
| `json_parse` | 54.324 | 432.409 | **486.733** | 111.784 | 159.831 | 176.342 |
| `nbody` | 4.730 | 126.931 | **131.661** | 60.610 | 125.582 | 101.763 |

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
