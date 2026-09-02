# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-02T04:34:31Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `dfb5c7dd951c2343dafa1bd75e0fd76670cda92c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33591017075 |
| NURL | `v0.58.0-4-gdfb5c7dd` |
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
| _(floor: empty program)_ | _1.444_ | _1.401_ | _1.633_ | _21.856_ | _16.826_ |
| `lcg` | 38.898 | **38.878** | 39.102 | 2074.347 | 5341.507 |
| `packet_classifier` | **56.141** | 56.262 | 56.286 | 161.650 | 4602.044 |
| `ring_write` | 42.283 | **42.150** | 42.324 | 66.505 | 6112.574 |
| `histogram_bins` | **39.489** | 40.603 | 39.540 | 65.464 | 6221.381 |
| `prefix_scan` | 21.594 | **21.517** | 21.586 | 64.792 | 4676.944 |
| `binary_search` | 39.322 | 38.035 | **36.926** | 104.865 | 6202.286 |
| `sort_window` | 26.494 | **26.440** | 26.644 | 196.259 | 11598.970 |
| `bloom_filter` | 17.865 | **17.798** | 18.296 | 2851.704 | 7609.620 |
| `hash_join` | **26.741** | 27.840 | 29.332 | 3387.287 | 8815.085 |
| `sieve` | 18.362 | 17.944 | **17.819** | 65.225 | 3266.613 |
| `fib` | **25.086** | 29.738 | 25.234 | 130.275 | 1345.548 |
| `collatz` | 12.192 | **12.135** | 12.368 | 48.936 | 715.027 |
| `matmul` | 33.556 | **33.298** | 33.478 | 75.397 | 3098.221 |
| `json_parse` | 8.975 | **8.611** | 11.586 | 35.300 | 38.146 |
| `nbody` | 25.028 | 39.625 | **23.939** | 99.690 | 3064.579 |

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
| _(floor: empty program)_ | _2.624_ | _91.527_ | _**94.151**_ | _57.005_ | _75.000_ | _59.475_ |
| `lcg` | 2.752 | 102.804 | **105.556** | 56.856 | 86.958 | 66.738 |
| `packet_classifier` | 2.837 | 103.327 | **106.164** | 56.531 | 87.078 | 70.372 |
| `ring_write` | 2.904 | 104.686 | **107.590** | 57.130 | 89.254 | 68.470 |
| `histogram_bins` | 3.033 | 113.631 | **116.664** | 57.857 | 105.957 | 76.500 |
| `prefix_scan` | 3.054 | 105.174 | **108.228** | 57.440 | 93.967 | 72.785 |
| `binary_search` | 3.224 | 104.200 | **107.424** | 57.224 | 90.143 | 73.643 |
| `sort_window` | 3.249 | 106.789 | **110.038** | 57.258 | 99.544 | 78.766 |
| `bloom_filter` | 3.503 | 107.805 | **111.308** | 57.600 | 99.128 | 73.998 |
| `hash_join` | 6.027 | 254.752 | **260.779** | 60.860 | 216.323 | 126.096 |
| `sieve` | 3.162 | 103.175 | **106.337** | 57.039 | 98.630 | 79.574 |
| `fib` | 2.784 | 103.538 | **106.322** | 56.970 | 86.697 | 66.551 |
| `collatz` | 2.970 | 105.109 | **108.079** | 57.286 | 88.006 | 70.032 |
| `matmul` | 3.326 | 105.118 | **108.444** | 57.578 | 102.567 | 90.853 |
| `json_parse` | 56.612 | 451.773 | **508.385** | 112.386 | 157.810 | 175.119 |
| `nbody` | 4.695 | 124.824 | **129.519** | 59.013 | 123.494 | 101.523 |

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
