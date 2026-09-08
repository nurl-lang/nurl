# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-08T19:38:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `bd633c7ec421c32be51986ce7da431e10155b438` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34269636238 |
| NURL | `v0.62.0` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
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
| _(floor: empty program)_ | _1.480_ | _1.448_ | _1.639_ | _25.587_ | _19.348_ |
| `lcg` | **39.177** | 39.349 | 39.448 | 2055.556 | 5240.093 |
| `packet_classifier` | 56.399 | **56.343** | 56.541 | 161.942 | 4384.090 |
| `ring_write` | **42.296** | 42.366 | 42.528 | 68.473 | 6352.325 |
| `histogram_bins` | **39.644** | 40.751 | 39.877 | 67.384 | 6338.961 |
| `prefix_scan` | **21.810** | 21.833 | 21.920 | 66.188 | 4559.934 |
| `binary_search` | 39.686 | 38.395 | **37.129** | 108.358 | 6393.157 |
| `sort_window` | **26.680** | 26.705 | 27.001 | 198.392 | 11527.359 |
| `bloom_filter` | **18.107** | 18.112 | 18.590 | 2882.516 | 7770.017 |
| `hash_join` | **26.847** | 28.131 | 29.751 | 3403.745 | 8441.144 |
| `sieve` | 18.964 | **18.491** | 18.596 | 68.442 | 3288.809 |
| `fib` | **25.276** | 30.053 | 25.555 | 133.380 | 1355.451 |
| `collatz` | **12.395** | 12.511 | 12.602 | 52.178 | 727.491 |
| `matmul` | 33.802 | **33.716** | 33.915 | 77.873 | 3138.959 |
| `json_parse` | 9.593 | **8.998** | 11.947 | 39.012 | 41.118 |
| `nbody` | 25.437 | 39.967 | **24.281** | 103.705 | 3075.859 |

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
| _(floor: empty program)_ | _27.703_ | _122.904_ | _**150.607**_ | _91.278_ | _82.650_ | _54.077_ |
| `lcg` | 2.877 | 112.733 | **115.610** | 62.515 | 93.429 | 61.149 |
| `packet_classifier` | 2.879 | 108.473 | **111.352** | 60.624 | 92.605 | 59.888 |
| `ring_write` | 3.068 | 111.441 | **114.509** | 60.645 | 94.288 | 61.077 |
| `histogram_bins` | 3.082 | 119.823 | **122.905** | 59.694 | 112.049 | 68.701 |
| `prefix_scan` | 3.167 | 113.891 | **117.058** | 61.913 | 100.754 | 65.576 |
| `binary_search` | 3.284 | 112.563 | **115.847** | 61.684 | 95.160 | 66.161 |
| `sort_window` | 3.440 | 115.987 | **119.427** | 61.933 | 107.064 | 72.456 |
| `bloom_filter` | 3.592 | 114.632 | **118.224** | 62.133 | 104.844 | 67.771 |
| `hash_join` | 6.329 | 261.245 | **267.574** | 63.911 | 222.713 | 115.865 |
| `sieve` | 3.209 | 113.666 | **116.875** | 62.395 | 107.620 | 71.786 |
| `fib` | 2.962 | 111.086 | **114.048** | 61.829 | 93.172 | 59.800 |
| `collatz` | 3.044 | 112.380 | **115.424** | 61.007 | 93.787 | 62.330 |
| `matmul` | 3.443 | 113.337 | **116.780** | 62.609 | 110.002 | 86.337 |
| `json_parse` | 60.066 | 473.836 | **533.902** | 121.566 | 167.644 | 175.402 |
| `nbody` | 4.890 | 134.732 | **139.622** | 64.395 | 131.354 | 93.342 |

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
