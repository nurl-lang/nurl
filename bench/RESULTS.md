# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-27T08:48:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `81a510898595fcb426201aa3f137db4d251d033f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33055339284 |
| NURL | `v0.53.0-6-g81a51089` |
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
| _(floor: empty program)_ | _1.560_ | _1.542_ | _1.752_ | _25.923_ | _18.724_ |
| `lcg` | 44.363 | **44.221** | 44.467 | 1815.765 | 5476.187 |
| `packet_classifier` | 63.506 | **63.485** | 63.688 | 158.265 | 5032.591 |
| `ring_write` | 47.603 | **47.573** | 47.770 | 73.978 | 6473.513 |
| `histogram_bins` | 44.581 | **44.562** | 44.867 | 76.670 | 6566.039 |
| `prefix_scan` | 24.504 | **24.431** | 24.669 | 71.897 | 5377.114 |
| `binary_search` | **33.852** | 35.480 | 36.502 | 110.761 | 6486.732 |
| `sort_window` | **30.145** | 30.418 | 30.187 | 165.641 | 12115.516 |
| `bloom_filter` | 19.744 | **18.720** | 20.599 | 2754.364 | 7888.331 |
| `hash_join` | **27.836** | 28.700 | 30.253 | 3514.118 | 8266.267 |
| `sieve` | 21.073 | **20.557** | 20.880 | 73.509 | 3491.191 |
| `fib` | **28.177** | 33.361 | 28.225 | 143.859 | 1290.036 |
| `collatz` | 13.836 | **13.734** | 14.027 | 55.341 | 754.568 |
| `matmul` | **45.721** | 46.198 | 46.622 | 84.419 | 3449.881 |
| `json_parse` | **8.807** | 8.924 | 12.559 | 40.789 | 40.203 |
| `nbody` | 26.853 | 45.045 | **26.398** | 97.867 | 3215.983 |

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
| _(floor: empty program)_ | _3.558_ | _105.659_ | _**109.217**_ | _67.912_ | _94.373_ | _68.848_ |
| `lcg` | 3.210 | 109.000 | **112.210** | 66.335 | 101.694 | 77.640 |
| `packet_classifier` | 3.266 | 108.473 | **111.739** | 66.778 | 103.158 | 78.520 |
| `ring_write` | 3.386 | 106.909 | **110.295** | 65.171 | 102.420 | 76.905 |
| `histogram_bins` | 3.440 | 125.726 | **129.166** | 65.845 | 118.092 | 84.760 |
| `prefix_scan` | 3.467 | 112.005 | **115.472** | 65.990 | 106.392 | 81.020 |
| `binary_search` | 3.644 | 115.954 | **119.598** | 67.072 | 102.873 | 83.036 |
| `sort_window` | 3.644 | 118.790 | **122.434** | 66.424 | 114.003 | 97.350 |
| `bloom_filter` | 3.974 | 114.126 | **118.100** | 67.056 | 110.709 | 83.968 |
| `hash_join` | 6.427 | 257.192 | **263.619** | 69.586 | 218.819 | 136.172 |
| `sieve` | 3.587 | 114.425 | **118.012** | 69.134 | 115.166 | 93.250 |
| `fib` | 3.215 | 109.311 | **112.526** | 68.300 | 103.929 | 77.247 |
| `collatz` | 3.464 | 113.954 | **117.418** | 68.581 | 106.053 | 81.865 |
| `matmul` | 3.874 | 116.111 | **119.985** | 69.213 | 119.373 | 106.550 |
| `json_parse` | 55.132 | 433.558 | **488.690** | 122.374 | 173.044 | 196.817 |
| `nbody` | 5.160 | 139.851 | **145.011** | 69.632 | 137.674 | 113.564 |

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
