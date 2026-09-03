# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-03T04:41:54Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `83540e79e2c964bb507e7773667534138404e49c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33715711523 |
| NURL | `v0.58.0-21-g83540e79` |
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
| _(floor: empty program)_ | _1.564_ | _1.528_ | _1.759_ | _24.301_ | _17.520_ |
| `lcg` | 44.074 | **44.043** | 44.227 | 1821.964 | 5636.045 |
| `packet_classifier` | 63.440 | **63.383** | 63.640 | 157.986 | 4613.568 |
| `ring_write` | **47.552** | 47.559 | 47.708 | 72.428 | 6745.969 |
| `histogram_bins` | **44.482** | 44.534 | 44.733 | 74.478 | 6761.147 |
| `prefix_scan` | 24.399 | **24.356** | 24.577 | 70.341 | 4830.343 |
| `binary_search` | 41.419 | **35.771** | 36.536 | 112.424 | 6402.160 |
| `sort_window` | 29.983 | **29.928** | 30.127 | 164.842 | 11409.236 |
| `bloom_filter` | 19.652 | **18.675** | 20.620 | 2726.342 | 7859.665 |
| `hash_join` | **27.611** | 28.694 | 30.031 | 3413.765 | 8480.502 |
| `sieve` | 20.242 | **19.915** | 20.140 | 71.090 | 3442.221 |
| `fib` | **27.886** | 33.051 | 28.066 | 142.758 | 1285.910 |
| `collatz` | 13.691 | **13.562** | 13.825 | 51.325 | 767.280 |
| `matmul` | **44.859** | 45.915 | 46.275 | 83.308 | 3606.397 |
| `json_parse` | 8.862 | **8.786** | 12.224 | 36.632 | 37.750 |
| `nbody` | 26.643 | 44.936 | **26.157** | 94.740 | 3315.424 |

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
| _(floor: empty program)_ | _2.916_ | _100.385_ | _**103.301**_ | _63.107_ | _84.274_ | _64.296_ |
| `lcg` | 3.059 | 111.549 | **114.608** | 63.149 | 94.027 | 72.150 |
| `packet_classifier` | 3.173 | 112.481 | **115.654** | 63.025 | 94.951 | 71.997 |
| `ring_write` | 3.268 | 113.471 | **116.739** | 63.415 | 96.940 | 76.242 |
| `histogram_bins` | 3.342 | 122.386 | **125.728** | 64.091 | 113.362 | 80.962 |
| `prefix_scan` | 3.353 | 114.801 | **118.154** | 63.321 | 102.018 | 77.327 |
| `binary_search` | 3.585 | 114.627 | **118.212** | 63.775 | 97.978 | 78.990 |
| `sort_window` | 3.560 | 116.604 | **120.164** | 64.239 | 107.596 | 83.812 |
| `bloom_filter` | 3.879 | 117.685 | **121.564** | 64.805 | 105.668 | 79.551 |
| `hash_join` | 6.350 | 254.345 | **260.695** | 67.723 | 212.458 | 127.426 |
| `sieve` | 3.482 | 114.631 | **118.113** | 63.811 | 107.582 | 84.132 |
| `fib` | 3.122 | 112.856 | **115.978** | 64.340 | 94.641 | 71.512 |
| `collatz` | 3.305 | 116.053 | **119.358** | 64.216 | 96.586 | 74.589 |
| `matmul` | 3.660 | 114.488 | **118.148** | 64.023 | 109.079 | 97.210 |
| `json_parse` | 56.116 | 437.540 | **493.656** | 118.013 | 160.837 | 181.603 |
| `nbody` | 5.049 | 131.682 | **136.731** | 65.689 | 129.603 | 105.975 |

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
