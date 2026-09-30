# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-30T16:50:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `8379113f61f90dc16bd94672ac4ecc6e958a2261` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36746503034 |
| NURL | `v0.67.0-11-g8379113f` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
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
| _(floor: empty program)_ | _1.452_ | _1.409_ | _1.614_ | _22.285_ | _16.945_ |
| `lcg` | 39.124 | **38.965** | 39.251 | 1886.434 | 5097.856 |
| `packet_classifier` | 56.340 | **56.282** | 56.391 | 161.291 | 4511.514 |
| `ring_write` | **42.156** | 42.190 | 42.316 | 64.412 | 7070.650 |
| `histogram_bins` | **39.385** | 40.508 | 39.619 | 65.100 | 5943.318 |
| `prefix_scan` | 21.630 | **21.622** | 21.693 | 63.940 | 4515.056 |
| `binary_search` | 39.433 | 38.123 | **37.030** | 105.462 | 6843.962 |
| `sort_window` | 26.624 | **26.459** | 26.819 | 199.081 | 12105.743 |
| `bloom_filter` | **16.592** | 17.833 | 18.375 | 2853.644 | 7589.122 |
| `hash_join` | **27.050** | 28.057 | 29.362 | 3414.543 | 8372.379 |
| `sieve` | 18.244 | 18.409 | **17.757** | 65.537 | 3264.966 |
| `fib` | 25.344 | 29.899 | **25.222** | 131.548 | 1360.994 |
| `collatz` | 12.290 | **12.161** | 12.379 | 50.307 | 740.048 |
| `matmul` | 33.442 | **33.393** | 33.728 | 76.169 | 3160.861 |
| `json_parse` | 8.681 | **8.527** | 11.505 | 36.191 | 38.972 |
| `nbody` | 25.105 | 39.705 | **24.017** | 100.588 | 3177.329 |

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
| _(floor: empty program)_ | _3.272_ | _97.094_ | _**100.366**_ | _58.460_ | _76.316_ | _62.362_ |
| `lcg` | 3.502 | 105.988 | **109.490** | 58.046 | 87.159 | 71.913 |
| `packet_classifier` | 3.656 | 107.825 | **111.481** | 58.429 | 89.171 | 68.601 |
| `ring_write` | 3.890 | 111.148 | **115.038** | 61.225 | 90.868 | 70.876 |
| `histogram_bins` | 3.921 | 114.337 | **118.258** | 58.691 | 106.958 | 77.662 |
| `prefix_scan` | 4.013 | 109.093 | **113.106** | 59.567 | 94.303 | 73.500 |
| `binary_search` | 4.162 | 106.889 | **111.051** | 59.061 | 90.878 | 76.562 |
| `sort_window` | 4.383 | 115.228 | **119.611** | 61.731 | 101.627 | 81.290 |
| `bloom_filter` | 4.918 | 111.717 | **116.635** | 60.005 | 99.766 | 74.169 |
| `hash_join` | 9.123 | 257.290 | **266.413** | 64.413 | 221.500 | 126.293 |
| `sieve` | 4.085 | 109.951 | **114.036** | 61.265 | 102.035 | 80.525 |
| `fib` | 3.639 | 111.437 | **115.076** | 61.522 | 91.381 | 69.298 |
| `collatz` | 3.922 | 111.284 | **115.206** | 60.671 | 92.368 | 74.270 |
| `matmul` | 4.593 | 113.811 | **118.404** | 63.486 | 105.878 | 94.973 |
| `json_parse` | 102.418 | 454.179 | **556.597** | 159.539 | 160.988 | 182.085 |
| `nbody` | 6.851 | 128.542 | **135.393** | 63.686 | 129.647 | 105.965 |

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
