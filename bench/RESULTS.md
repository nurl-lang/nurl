# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-22T20:25:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377732 KiB |
| Commit | `deca4334926431dc1c87c8706fdf3fd273ec2d8f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32596420060 |
| NURL | `v0.49.0-5-gdeca4334` |
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
| _(floor: empty program)_ | _1.434_ | _1.413_ | _1.618_ | _22.534_ | _16.871_ |
| `lcg` | 39.140 | **39.039** | 39.318 | 2042.629 | 5228.618 |
| `packet_classifier` | 56.198 | **56.106** | 56.585 | 162.015 | 4462.457 |
| `ring_write` | 42.203 | **42.092** | 42.244 | 65.590 | 6162.832 |
| `histogram_bins` | **39.494** | 40.481 | 39.696 | 66.209 | 6048.997 |
| `prefix_scan` | 21.676 | **21.637** | 21.725 | 64.065 | 4716.443 |
| `binary_search` | **36.210** | 38.117 | 37.249 | 105.235 | 6420.704 |
| `sort_window` | 26.609 | **26.420** | 26.715 | 197.476 | 11290.271 |
| `bloom_filter` | 18.004 | **17.769** | 18.305 | 2840.594 | 7659.602 |
| `hash_join` | **26.820** | 27.852 | 29.242 | 3393.680 | 8276.855 |
| `sieve` | 20.379 | **19.830** | 20.053 | 66.671 | 3324.282 |
| `fib` | **25.078** | 29.897 | 25.471 | 131.157 | 1344.475 |
| `collatz` | **12.145** | 12.170 | 12.323 | 49.137 | 711.979 |
| `matmul` | 43.115 | **33.213** | 33.475 | 77.046 | 3439.512 |
| `json_parse` | 8.937 | **8.532** | 11.488 | 35.681 | 36.902 |
| `nbody` | 25.269 | 39.885 | **24.095** | 98.670 | 3051.179 |

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
| _(floor: empty program)_ | _2.628_ | _90.942_ | _**93.570**_ | _58.035_ | _81.229_ | _54.040_ |
| `lcg` | 2.773 | 92.937 | **95.710** | 56.624 | 88.928 | 58.985 |
| `packet_classifier` | 2.859 | 93.386 | **96.245** | 59.772 | 88.919 | 60.385 |
| `ring_write` | 2.940 | 95.265 | **98.205** | 57.441 | 90.599 | 61.338 |
| `histogram_bins` | 3.052 | 112.838 | **115.890** | 57.701 | 106.884 | 67.936 |
| `prefix_scan` | 3.054 | 98.122 | **101.176** | 56.824 | 95.265 | 63.476 |
| `binary_search` | 3.227 | 102.862 | **106.089** | 58.872 | 93.148 | 66.011 |
| `sort_window` | 3.273 | 106.189 | **109.462** | 57.407 | 104.098 | 70.814 |
| `bloom_filter` | 3.506 | 101.801 | **105.307** | 57.531 | 99.868 | 66.194 |
| `hash_join` | 5.980 | 254.396 | **260.376** | 61.260 | 216.934 | 113.192 |
| `sieve` | 3.111 | 96.022 | **99.133** | 57.472 | 100.363 | 70.782 |
| `fib` | 2.815 | 95.175 | **97.990** | 57.183 | 88.364 | 58.095 |
| `collatz` | 3.061 | 97.190 | **100.251** | 57.507 | 90.018 | 61.440 |
| `matmul` | 3.339 | 99.489 | **102.828** | 58.071 | 105.779 | 82.821 |
| `json_parse` | 52.170 | 431.273 | **483.443** | 108.778 | 159.000 | 162.069 |
| `nbody` | 4.658 | 123.306 | **127.964** | 58.881 | 129.616 | 90.767 |

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
