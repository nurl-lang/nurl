# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-08T03:35:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `20b76fd965c43bccd0d45ca27cf1bbf258404e0b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37723107195 |
| NURL | `v0.70.0-41-g20b76fd9` |
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
| _(floor: empty program)_ | _1.207_ | _1.188_ | _1.403_ | _20.941_ | _14.098_ |
| `lcg` | 34.191 | **34.179** | 34.281 | 1412.221 | 4145.029 |
| `packet_classifier` | **49.159** | 49.166 | 49.280 | 123.002 | 3572.470 |
| `ring_write` | 36.910 | **36.813** | 36.948 | 56.919 | 5465.946 |
| `histogram_bins` | **34.510** | 34.535 | 34.649 | 57.525 | 4893.105 |
| `prefix_scan` | 18.890 | **18.877** | 19.073 | 55.986 | 3588.823 |
| `binary_search` | 32.069 | **27.627** | 33.396 | 88.912 | 5418.702 |
| `sort_window` | 23.462 | **23.396** | 23.584 | 130.524 | 8780.983 |
| `bloom_filter` | **13.433** | 14.519 | 16.011 | 2112.089 | 5935.664 |
| `hash_join` | **21.336** | 22.099 | 23.336 | 2715.984 | 6658.094 |
| `sieve` | 16.013 | **15.958** | 16.007 | 56.971 | 2612.056 |
| `fib` | **21.656** | 25.664 | 25.948 | 111.691 | 997.927 |
| `collatz` | **10.558** | 10.577 | 10.741 | 41.181 | 582.852 |
| `matmul` | **34.980** | 35.475 | 35.497 | 65.721 | 2712.776 |
| `json_parse` | **6.268** | 6.863 | 9.380 | 29.292 | 30.621 |
| `nbody` | **20.739** | 34.898 | 20.831 | 76.365 | 2768.243 |

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
| _(floor: empty program)_ | _3.214_ | _87.642_ | _**90.856**_ | _55.067_ | _73.725_ | _51.020_ |
| `lcg` | 3.298 | 96.751 | **100.049** | 53.445 | 79.028 | 58.084 |
| `packet_classifier` | 3.346 | 97.951 | **101.297** | 54.936 | 78.994 | 57.385 |
| `ring_write` | 3.556 | 99.390 | **102.946** | 55.865 | 81.195 | 61.006 |
| `histogram_bins` | 3.533 | 102.692 | **106.225** | 55.076 | 92.241 | 65.406 |
| `prefix_scan` | 3.651 | 100.397 | **104.048** | 54.535 | 85.865 | 62.409 |
| `binary_search` | 3.822 | 96.641 | **100.463** | 53.792 | 80.585 | 64.786 |
| `sort_window` | 3.954 | 135.547 | **139.501** | 59.497 | 89.541 | 68.714 |
| `bloom_filter` | 4.407 | 102.043 | **106.450** | 55.263 | 90.131 | 64.530 |
| `hash_join` | 7.203 | 207.522 | **214.725** | 57.551 | 173.456 | 100.135 |
| `sieve` | 3.958 | 100.498 | **104.456** | 55.782 | 90.146 | 70.404 |
| `fib` | 3.395 | 97.947 | **101.342** | 54.330 | 79.647 | 59.672 |
| `collatz` | 3.604 | 100.479 | **104.083** | 55.417 | 83.782 | 61.454 |
| `matmul` | 4.818 | 99.404 | **104.222** | 55.611 | 90.785 | 74.989 |
| `json_parse` | 36.458 | 360.180 | **396.638** | 88.439 | 129.786 | 139.421 |
| `nbody` | 5.829 | 116.036 | **121.865** | 58.489 | 107.831 | 90.233 |

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
