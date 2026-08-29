# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T13:56:34Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `26a5eb4dab6b12c6d69bc0969ba3f2e73d474605` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33256108697 |
| NURL | `v0.56.0` |
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
| _(floor: empty program)_ | _1.124_ | _1.087_ | _1.228_ | _18.864_ | _13.662_ |
| `lcg` | 35.246 | **35.016** | 35.050 | 1371.795 | 3795.038 |
| `packet_classifier` | 59.837 | **59.173** | 59.704 | 145.142 | 3075.512 |
| `ring_write` | 38.375 | **38.260** | 38.677 | 58.034 | 4361.710 |
| `histogram_bins` | 35.862 | **35.833** | 35.976 | 58.990 | 4192.708 |
| `prefix_scan` | 19.182 | **19.104** | 19.640 | 54.857 | 3131.841 |
| `binary_search` | 34.139 | 27.590 | **26.471** | 95.790 | 4543.518 |
| `sort_window` | **34.389** | 34.405 | 35.401 | 155.295 | 9541.174 |
| `bloom_filter` | 12.261 | **12.259** | 12.521 | 2116.218 | 5805.584 |
| `hash_join` | **20.439** | 21.768 | 22.023 | 2651.934 | 6076.668 |
| `sieve` | 33.382 | **32.934** | 33.325 | 74.316 | 2400.943 |
| `fib` | 24.612 | 26.220 | **24.569** | 97.414 | 779.281 |
| `collatz` | **13.051** | 13.146 | 13.757 | 51.142 | 490.909 |
| `matmul` | 17.628 | **17.456** | 17.500 | 63.252 | 2181.217 |
| `json_parse` | 6.711 | **6.435** | 8.298 | 27.064 | 28.183 |
| `nbody` | 19.396 | 27.181 | **19.369** | 69.868 | 1846.079 |

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
| _(floor: empty program)_ | _2.011_ | _62.490_ | _**64.501**_ | _38.501_ | _49.322_ | _50.877_ |
| `lcg` | 2.119 | 76.041 | **78.160** | 39.002 | 56.178 | 56.116 |
| `packet_classifier` | 2.200 | 71.947 | **74.147** | 38.738 | 56.430 | 53.828 |
| `ring_write` | 2.281 | 72.456 | **74.737** | 39.082 | 56.613 | 54.897 |
| `histogram_bins` | 2.294 | 80.242 | **82.536** | 38.591 | 70.410 | 60.730 |
| `prefix_scan` | 2.436 | 73.494 | **75.930** | 39.170 | 60.890 | 56.918 |
| `binary_search` | 2.514 | 74.905 | **77.419** | 40.368 | 58.057 | 59.784 |
| `sort_window` | 2.535 | 73.909 | **76.444** | 38.805 | 65.767 | 64.203 |
| `bloom_filter` | 2.806 | 74.402 | **77.208** | 39.989 | 63.727 | 61.583 |
| `hash_join` | 4.834 | 181.740 | **186.574** | 43.003 | 146.508 | 103.034 |
| `sieve` | 2.481 | 71.747 | **74.228** | 38.903 | 64.646 | 65.869 |
| `fib` | 2.216 | 71.567 | **73.783** | 38.938 | 55.202 | 51.802 |
| `collatz` | 2.308 | 72.849 | **75.157** | 38.519 | 57.412 | 55.640 |
| `matmul` | 2.606 | 72.493 | **75.099** | 39.313 | 66.085 | 76.388 |
| `json_parse` | 43.358 | 316.099 | **359.457** | 82.773 | 107.468 | 153.091 |
| `nbody` | 3.517 | 87.593 | **91.110** | 41.017 | 82.449 | 83.449 |

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
