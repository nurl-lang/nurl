# Cloud benchmark results — NURL vs C vs Rust vs Node vs Python

A one-off run of `bench/bench.sh` in a Claude Code cloud container,
`2026-09-24T20:01:06Z`. It is a snapshot kept for comparison, **not** the
published numbers: those are [`RESULTS.md`](RESULTS.md) and
[`results/latest.json`](results/latest.json), refreshed by CI on a fixed
runner. Nothing regenerates this file.

## Environment

| Item | Value |
|---|---|
| Host | `Linux x86_64` |
| Kernel | `Linux 6.18.44-fc-v37 x86_64` |
| CPU | Intel(R) Xeon(R) Processor @ 2.10GHz (4 logical cores) |
| Memory | 16481980 KiB |
| Commit | `3ae7fc78b74d47bef6d4779b29d9fb042005ebe0` |
| NURL | `v0.66.0` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.94.1 (e408947bf 2026-03-25) |
| Node | v22.22.2 |
| Python | Python 3.11.15 |

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
| _(floor: empty program)_ | _2.569_ | _2.526_ | _3.027_ | _30.028_ | _12.386_ |
| `lcg` | 42.387 | **40.223** | 42.622 | 1578.054 | 3591.355 |
| `packet_classifier` | **69.249** | 70.262 | 70.381 | 181.715 | 3137.516 |
| `ring_write` | 45.389 | 45.469 | **44.617** | 77.128 | 4700.112 |
| `histogram_bins` | **41.812** | 42.703 | 41.939 | 75.024 | 5111.351 |
| `prefix_scan` | **21.954** | 22.683 | 23.639 | 73.142 | 3594.637 |
| `binary_search` | 37.382 | **30.698** | 30.885 | 120.601 | 6049.053 |
| `sort_window` | **40.066** | 40.231 | 41.129 | 187.568 | 9684.978 |
| `bloom_filter` | **14.832** | 15.030 | 15.488 | 2475.262 | 6632.463 |
| `hash_join` | **25.060** | 32.101 | 26.822 | 3287.639 | 6501.924 |
| `sieve` | 52.767 | **52.639** | 57.948 | 112.346 | 2581.276 |
| `fib` | **24.332** | 28.026 | 30.717 | 128.066 | 1048.937 |
| `collatz` | **15.756** | 16.741 | 16.838 | 68.500 | 542.150 |
| `matmul` | 21.070 | 20.746 | **17.454** | 82.188 | 2791.707 |
| `json_parse` | 9.623 | **8.805** | 10.918 | 38.921 | 32.638 |
| `nbody` | 22.288 | 30.803 | **22.112** | 95.548 | 2288.142 |

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
| _(floor: empty program)_ | _5.158_ | _127.529_ | _**132.687**_ | _86.678_ | _86.004_ | _116.163_ |
| `lcg` | 5.030 | 167.216 | **172.246** | 99.304 | 105.610 | 103.721 |
| `packet_classifier` | 5.191 | 120.533 | **125.724** | 68.932 | 88.768 | 87.671 |
| `ring_write` | 5.330 | 118.293 | **123.623** | 62.477 | 97.345 | 92.090 |
| `histogram_bins` | 4.893 | 120.698 | **125.591** | 66.198 | 125.937 | 100.033 |
| `prefix_scan` | 5.825 | 114.436 | **120.261** | 63.211 | 97.742 | 88.013 |
| `binary_search` | 5.391 | 119.694 | **125.085** | 73.805 | 107.310 | 94.005 |
| `sort_window` | 5.383 | 111.284 | **116.667** | 66.142 | 109.794 | 94.743 |
| `bloom_filter` | 5.951 | 120.585 | **126.536** | 64.546 | 104.517 | 97.431 |
| `hash_join` | 11.564 | 246.804 | **258.368** | 75.567 | 214.835 | 154.564 |
| `sieve` | 5.261 | 117.435 | **122.696** | 68.717 | 103.731 | 115.307 |
| `fib` | 5.003 | 119.803 | **124.806** | 61.593 | 89.566 | 79.359 |
| `collatz` | 5.428 | 129.104 | **134.532** | 66.490 | 102.628 | 110.862 |
| `matmul` | 5.923 | 115.671 | **121.594** | 66.126 | 106.658 | 133.891 |
| `json_parse` | 95.098 | 440.632 | **535.730** | 155.025 | 146.554 | 262.433 |
| `nbody` | 6.852 | 134.770 | **141.622** | 70.271 | 123.625 | 127.755 |

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
