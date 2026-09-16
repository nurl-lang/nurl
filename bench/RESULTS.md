# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-16T04:33:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ccb9396891e8fdd863cd5c4f1472bd8d6614d9d4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/35055767135 |
| NURL | `v0.66.0` |
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
| _(floor: empty program)_ | _1.411_ | _1.412_ | _1.620_ | _23.585_ | _17.900_ |
| `lcg` | 38.974 | **38.921** | 39.081 | 2051.192 | 5163.322 |
| `packet_classifier` | 56.294 | **56.135** | 56.457 | 162.840 | 4225.812 |
| `ring_write` | 42.309 | **42.054** | 42.467 | 66.176 | 6610.295 |
| `histogram_bins` | **39.465** | 40.598 | 39.700 | 65.722 | 6260.229 |
| `prefix_scan` | **21.600** | 21.811 | 21.800 | 64.971 | 4393.258 |
| `binary_search` | 39.482 | 38.261 | **36.927** | 106.023 | 6511.211 |
| `sort_window` | **26.566** | 26.615 | 26.704 | 197.820 | 11378.153 |
| `bloom_filter` | **16.687** | 17.840 | 18.363 | 2864.064 | 7705.976 |
| `hash_join` | **26.813** | 27.956 | 29.427 | 3492.243 | 8539.072 |
| `sieve` | 19.873 | 20.000 | **19.704** | 66.549 | 3130.948 |
| `fib` | **25.065** | 29.797 | 25.228 | 132.222 | 1366.507 |
| `collatz` | 12.216 | **12.193** | 12.344 | 49.535 | 720.518 |
| `matmul` | **33.406** | 33.437 | 33.670 | 77.590 | 3198.335 |
| `json_parse` | 9.752 | **8.613** | 13.235 | 35.230 | 39.641 |
| `nbody` | 25.118 | 39.563 | **24.056** | 102.172 | 3134.600 |

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
| _(floor: empty program)_ | _3.173_ | _94.667_ | _**97.840**_ | _57.684_ | _76.980_ | _60.361_ |
| `lcg` | 3.418 | 108.388 | **111.806** | 59.128 | 86.907 | 67.974 |
| `packet_classifier` | 3.561 | 106.037 | **109.598** | 58.069 | 87.438 | 67.298 |
| `ring_write` | 3.725 | 107.189 | **110.914** | 58.902 | 89.027 | 70.272 |
| `histogram_bins` | 3.797 | 115.105 | **118.902** | 59.397 | 108.244 | 77.482 |
| `prefix_scan` | 3.915 | 108.678 | **112.593** | 58.502 | 94.132 | 71.740 |
| `binary_search` | 4.240 | 108.680 | **112.920** | 59.550 | 93.257 | 75.214 |
| `sort_window` | 4.350 | 111.842 | **116.192** | 59.815 | 100.664 | 80.776 |
| `bloom_filter` | 4.809 | 112.955 | **117.764** | 60.532 | 100.905 | 75.782 |
| `hash_join` | 9.143 | 256.574 | **265.717** | 63.568 | 217.661 | 137.502 |
| `sieve` | 3.994 | 106.311 | **110.305** | 59.943 | 100.660 | 78.904 |
| `fib` | 3.398 | 105.233 | **108.631** | 57.602 | 87.021 | 65.914 |
| `collatz` | 3.737 | 108.614 | **112.351** | 58.316 | 88.709 | 70.908 |
| `matmul` | 4.407 | 107.270 | **111.677** | 59.583 | 102.612 | 92.064 |
| `json_parse` | 101.737 | 469.486 | **571.223** | 159.840 | 160.030 | 175.676 |
| `nbody` | 6.559 | 125.791 | **132.350** | 61.630 | 124.354 | 99.523 |

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
