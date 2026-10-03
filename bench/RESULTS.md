# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-03T18:41:25Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0b978b9247025179abb15434544f5336176206be` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37144829527 |
| NURL | `v0.69.1` |
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
| _(floor: empty program)_ | _1.450_ | _1.432_ | _1.636_ | _22.200_ | _17.697_ |
| `lcg` | 39.169 | **39.015** | 39.432 | 1913.546 | 5298.942 |
| `packet_classifier` | **56.199** | 56.214 | 56.425 | 162.418 | 4318.004 |
| `ring_write` | 42.229 | **42.177** | 42.361 | 67.169 | 6570.389 |
| `histogram_bins` | **39.423** | 40.578 | 40.806 | 66.249 | 6403.896 |
| `prefix_scan` | **21.619** | 21.653 | 21.865 | 65.277 | 4587.040 |
| `binary_search` | 39.601 | **38.379** | 41.245 | 106.751 | 8677.190 |
| `sort_window` | 26.600 | **26.552** | 26.730 | 197.645 | 11548.773 |
| `bloom_filter` | **16.546** | 17.871 | 18.354 | 2843.771 | 7597.861 |
| `hash_join` | **27.048** | 27.915 | 29.371 | 3417.017 | 8303.807 |
| `sieve` | **20.180** | 20.211 | 20.191 | 69.237 | 3184.687 |
| `fib` | **25.113** | 29.793 | 30.074 | 132.747 | 1379.610 |
| `collatz` | 12.290 | **12.223** | 12.461 | 49.578 | 760.071 |
| `matmul` | 33.460 | **33.457** | 33.582 | 76.924 | 3226.629 |
| `json_parse` | 8.965 | **8.601** | 11.768 | 35.345 | 39.044 |
| `nbody` | 25.170 | 39.783 | **25.168** | 102.286 | 3106.960 |

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
| _(floor: empty program)_ | _3.437_ | _100.151_ | _**103.588**_ | _59.841_ | _78.036_ | _52.110_ |
| `lcg` | 3.677 | 111.094 | **114.771** | 59.686 | 89.564 | 57.138 |
| `packet_classifier` | 3.739 | 111.877 | **115.616** | 60.798 | 92.881 | 58.507 |
| `ring_write` | 3.951 | 110.252 | **114.203** | 60.025 | 90.526 | 59.060 |
| `histogram_bins` | 4.098 | 117.378 | **121.476** | 61.353 | 107.506 | 67.347 |
| `prefix_scan` | 4.044 | 109.910 | **113.954** | 60.389 | 96.334 | 62.950 |
| `binary_search` | 4.347 | 111.849 | **116.196** | 61.218 | 91.605 | 63.759 |
| `sort_window` | 4.471 | 112.167 | **116.638** | 59.392 | 101.467 | 68.854 |
| `bloom_filter` | 4.992 | 113.258 | **118.250** | 61.039 | 100.750 | 65.932 |
| `hash_join` | 9.252 | 264.158 | **273.410** | 69.230 | 222.772 | 109.975 |
| `sieve` | 4.116 | 109.995 | **114.111** | 60.352 | 104.428 | 69.536 |
| `fib` | 3.662 | 111.087 | **114.749** | 60.244 | 90.167 | 57.378 |
| `collatz` | 4.003 | 114.270 | **118.273** | 63.111 | 95.968 | 60.913 |
| `matmul` | 4.623 | 111.888 | **116.511** | 61.120 | 105.015 | 78.799 |
| `json_parse` | 104.319 | 459.648 | **563.967** | 162.661 | 161.535 | 158.841 |
| `nbody` | 6.718 | 130.386 | **137.104** | 63.912 | 132.236 | 95.016 |

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
