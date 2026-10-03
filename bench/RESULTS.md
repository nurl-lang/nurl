# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-03T18:17:24Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `0b978b9247025179abb15434544f5336176206be` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37143325536 |
| NURL | `v0.69.0-2-g0b978b92` |
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
| _(floor: empty program)_ | _1.478_ | _1.522_ | _1.698_ | _26.144_ | _18.118_ |
| `lcg` | 39.355 | **39.291** | 39.490 | 1892.450 | 5069.181 |
| `packet_classifier` | **56.329** | 56.367 | 56.648 | 162.632 | 4369.946 |
| `ring_write` | 42.477 | **42.326** | 42.733 | 67.740 | 6434.341 |
| `histogram_bins` | **39.682** | 40.951 | 41.146 | 68.708 | 6322.248 |
| `prefix_scan` | 21.859 | **21.775** | 21.986 | 65.214 | 4751.830 |
| `binary_search` | 39.566 | **38.166** | 41.343 | 110.633 | 6377.444 |
| `sort_window` | 26.636 | **26.565** | 26.942 | 198.376 | 11302.114 |
| `bloom_filter` | **16.746** | 17.963 | 18.519 | 2832.913 | 8031.162 |
| `hash_join` | **26.924** | 28.064 | 29.505 | 3456.499 | 8270.409 |
| `sieve` | 21.360 | **20.588** | 20.817 | 65.707 | 3422.713 |
| `fib` | **25.125** | 29.868 | 30.109 | 132.258 | 1370.693 |
| `collatz` | 12.214 | **12.180** | 12.395 | 49.627 | 737.846 |
| `matmul` | 33.497 | **33.206** | 33.557 | 75.002 | 3247.168 |
| `json_parse` | 9.216 | **8.893** | 11.971 | 36.876 | 38.944 |
| `nbody` | **25.226** | 39.897 | 25.249 | 102.511 | 3098.880 |

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
| _(floor: empty program)_ | _3.462_ | _105.524_ | _**108.986**_ | _65.193_ | _86.250_ | _55.162_ |
| `lcg` | 3.659 | 114.031 | **117.690** | 63.223 | 95.550 | 61.248 |
| `packet_classifier` | 3.759 | 113.843 | **117.602** | 62.555 | 95.699 | 60.739 |
| `ring_write` | 4.061 | 119.039 | **123.100** | 64.166 | 100.125 | 61.315 |
| `histogram_bins` | 4.039 | 120.033 | **124.072** | 62.823 | 112.507 | 70.567 |
| `prefix_scan` | 4.232 | 118.753 | **122.985** | 65.020 | 101.487 | 64.465 |
| `binary_search` | 4.219 | 115.534 | **119.753** | 64.635 | 99.764 | 66.535 |
| `sort_window` | 4.617 | 117.356 | **121.973** | 63.427 | 106.047 | 68.395 |
| `bloom_filter` | 5.031 | 117.289 | **122.320** | 63.369 | 105.624 | 67.803 |
| `hash_join` | 9.314 | 264.723 | **274.037** | 67.453 | 218.801 | 109.601 |
| `sieve` | 4.208 | 115.829 | **120.037** | 62.345 | 107.244 | 69.111 |
| `fib` | 3.673 | 112.180 | **115.853** | 62.260 | 92.448 | 56.900 |
| `collatz` | 4.085 | 118.859 | **122.944** | 64.538 | 96.779 | 58.665 |
| `matmul` | 4.776 | 119.095 | **123.871** | 65.660 | 109.126 | 79.146 |
| `json_parse` | 106.157 | 469.722 | **575.879** | 169.120 | 162.523 | 159.785 |
| `nbody` | 6.779 | 135.915 | **142.694** | 72.206 | 135.022 | 97.090 |

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
