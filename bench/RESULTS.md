# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-27T17:59:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `108addcd5bb091dfbc1b507a772e15316fd68a55` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33100827873 |
| NURL | `v0.53.0-9-g108addcd` |
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
| _(floor: empty program)_ | _1.638_ | _1.550_ | _1.785_ | _26.965_ | _19.401_ |
| `lcg` | 44.266 | **44.237** | 44.367 | 1819.353 | 5526.851 |
| `packet_classifier` | **63.459** | 63.589 | 63.883 | 160.412 | 4651.299 |
| `ring_write` | **47.677** | 47.751 | 47.941 | 74.619 | 6712.807 |
| `histogram_bins` | **44.666** | 44.754 | 44.905 | 77.353 | 6449.797 |
| `prefix_scan` | 24.545 | **24.501** | 24.683 | 71.462 | 4835.077 |
| `binary_search` | **33.365** | 35.643 | 36.578 | 112.849 | 6964.456 |
| `sort_window` | **30.062** | 30.138 | 30.380 | 167.702 | 11079.180 |
| `bloom_filter` | 19.717 | **18.801** | 20.622 | 2750.428 | 7800.293 |
| `hash_join` | **27.640** | 28.656 | 30.189 | 3435.533 | 8270.708 |
| `sieve` | 20.581 | **20.229** | 20.254 | 71.188 | 3719.144 |
| `fib` | **27.842** | 33.237 | 28.201 | 145.241 | 1293.995 |
| `collatz` | 13.738 | **13.697** | 13.993 | 53.413 | 753.965 |
| `matmul` | 46.145 | 46.340 | **45.580** | 83.148 | 3511.503 |
| `json_parse` | **8.719** | 8.761 | 12.221 | 39.108 | 38.220 |
| `nbody` | 26.786 | 45.103 | **26.309** | 96.208 | 3229.023 |

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
| _(floor: empty program)_ | _3.056_ | _107.809_ | _**110.865**_ | _67.846_ | _95.075_ | _70.023_ |
| `lcg` | 3.313 | 109.567 | **112.880** | 66.860 | 100.286 | 81.032 |
| `packet_classifier` | 3.201 | 105.424 | **108.625** | 65.308 | 99.355 | 75.099 |
| `ring_write` | 3.495 | 110.841 | **114.336** | 67.159 | 102.823 | 79.160 |
| `histogram_bins` | 3.510 | 130.232 | **133.742** | 68.039 | 122.579 | 90.303 |
| `prefix_scan` | 3.574 | 114.919 | **118.493** | 67.369 | 111.495 | 84.538 |
| `binary_search` | 3.681 | 114.559 | **118.240** | 66.880 | 101.121 | 83.952 |
| `sort_window` | 3.747 | 117.574 | **121.321** | 66.382 | 115.034 | 89.259 |
| `bloom_filter` | 4.078 | 116.098 | **120.176** | 68.188 | 113.931 | 86.501 |
| `hash_join` | 6.445 | 257.460 | **263.905** | 68.802 | 217.466 | 134.118 |
| `sieve` | 3.652 | 110.171 | **113.823** | 66.224 | 111.435 | 89.200 |
| `fib` | 3.191 | 107.943 | **111.134** | 65.781 | 101.521 | 75.773 |
| `collatz` | 3.378 | 112.090 | **115.468** | 67.471 | 103.132 | 80.081 |
| `matmul` | 3.745 | 114.206 | **117.951** | 66.152 | 114.183 | 103.785 |
| `json_parse` | 53.488 | 417.087 | **470.575** | 116.615 | 163.959 | 188.853 |
| `nbody` | 5.115 | 133.994 | **139.109** | 66.804 | 134.500 | 113.017 |

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
