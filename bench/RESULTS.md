# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-07T06:03:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373440 KiB |
| Commit | `897f58282745c31a893e91d712b07e068f7aefe3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37578978648 |
| NURL | `v0.70.0-24-g897f5828` |
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
| _(floor: empty program)_ | _1.451_ | _1.428_ | _1.614_ | _21.911_ | _17.271_ |
| `lcg` | 38.940 | **38.933** | 39.200 | 1942.290 | 5049.540 |
| `packet_classifier` | **56.162** | 56.290 | 56.275 | 161.748 | 4333.133 |
| `ring_write` | **42.086** | 42.167 | 42.388 | 66.068 | 6459.040 |
| `histogram_bins` | **39.421** | 40.742 | 40.920 | 66.649 | 6087.987 |
| `prefix_scan` | **21.565** | 21.587 | 21.789 | 64.087 | 4488.532 |
| `binary_search` | 39.328 | **38.006** | 40.916 | 105.605 | 6182.973 |
| `sort_window` | **26.520** | 26.554 | 26.771 | 196.941 | 11495.947 |
| `bloom_filter` | **15.343** | 17.730 | 18.343 | 2831.104 | 7514.386 |
| `hash_join` | **26.565** | 27.985 | 29.035 | 3517.969 | 8315.488 |
| `sieve` | 20.974 | **20.591** | 20.771 | 68.247 | 3403.434 |
| `fib` | **25.061** | 29.868 | 29.837 | 131.810 | 1360.254 |
| `collatz` | 12.216 | **12.154** | 12.478 | 49.040 | 738.452 |
| `matmul` | 33.490 | **33.468** | 33.672 | 76.088 | 3094.006 |
| `json_parse` | 8.904 | **8.564** | 11.807 | 34.818 | 38.588 |
| `nbody` | **25.042** | 39.712 | 25.177 | 99.120 | 3148.155 |

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
| _(floor: empty program)_ | _3.383_ | _97.777_ | _**101.160**_ | _59.383_ | _79.819_ | _63.239_ |
| `lcg` | 3.564 | 111.027 | **114.591** | 59.450 | 88.156 | 65.247 |
| `packet_classifier` | 3.780 | 111.295 | **115.075** | 60.133 | 89.786 | 65.906 |
| `ring_write` | 4.015 | 112.929 | **116.944** | 61.471 | 91.434 | 67.458 |
| `histogram_bins` | 4.094 | 122.310 | **126.404** | 62.004 | 109.418 | 75.733 |
| `prefix_scan` | 4.179 | 114.197 | **118.376** | 59.999 | 94.405 | 71.416 |
| `binary_search` | 4.254 | 112.696 | **116.950** | 61.992 | 95.885 | 74.514 |
| `sort_window` | 4.494 | 113.976 | **118.470** | 60.814 | 100.822 | 76.823 |
| `bloom_filter` | 4.966 | 114.877 | **119.843** | 60.662 | 100.682 | 76.093 |
| `hash_join` | 8.899 | 263.181 | **272.080** | 65.025 | 216.504 | 120.093 |
| `sieve` | 4.114 | 114.179 | **118.293** | 61.268 | 101.216 | 76.891 |
| `fib` | 3.666 | 111.199 | **114.865** | 60.340 | 89.609 | 64.413 |
| `collatz` | 3.979 | 114.811 | **118.790** | 60.979 | 90.543 | 67.613 |
| `matmul` | 4.796 | 114.280 | **119.076** | 62.680 | 105.097 | 87.514 |
| `json_parse` | 47.613 | 462.501 | **510.114** | 105.164 | 162.934 | 167.020 |
| `nbody` | 6.893 | 133.409 | **140.302** | 64.378 | 126.859 | 105.156 |

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
