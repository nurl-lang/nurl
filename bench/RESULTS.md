# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-30T14:15:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `40ec56dbcdb10db5c3d39b409ae6b7a6d9d54cb8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36727101395 |
| NURL | `v0.67.0-9-g40ec56db` |
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
| _(floor: empty program)_ | _1.548_ | _1.529_ | _1.773_ | _25.383_ | _18.729_ |
| `lcg` | 44.220 | **44.102** | 44.385 | 1819.142 | 5743.782 |
| `packet_classifier` | 63.565 | **63.561** | 63.800 | 161.580 | 4745.958 |
| `ring_write` | 47.710 | **47.686** | 47.840 | 72.468 | 6600.601 |
| `histogram_bins` | **44.654** | 44.677 | 44.987 | 75.653 | 6326.463 |
| `prefix_scan` | 24.463 | **24.434** | 24.759 | 74.191 | 4580.371 |
| `binary_search` | 41.358 | **35.907** | 36.855 | 114.464 | 6750.520 |
| `sort_window` | 30.392 | **30.051** | 30.280 | 166.256 | 11435.946 |
| `bloom_filter` | **17.321** | 18.714 | 20.625 | 2799.377 | 7723.879 |
| `hash_join` | **27.570** | 28.704 | 30.257 | 3396.309 | 8325.146 |
| `sieve` | 20.854 | **20.226** | 20.633 | 71.857 | 3411.345 |
| `fib` | **27.870** | 33.143 | 28.268 | 143.111 | 1292.688 |
| `collatz` | 13.745 | **13.644** | 13.852 | 53.793 | 766.114 |
| `matmul` | **45.477** | 46.657 | 46.175 | 83.918 | 3752.335 |
| `json_parse` | **8.485** | 8.830 | 12.137 | 40.147 | 41.164 |
| `nbody` | 26.758 | 44.995 | **26.271** | 96.529 | 3322.044 |

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
| _(floor: empty program)_ | _3.710_ | _107.982_ | _**111.692**_ | _66.603_ | _88.756_ | _65.266_ |
| `lcg` | 3.972 | 118.314 | **122.286** | 66.840 | 97.676 | 73.263 |
| `packet_classifier` | 4.082 | 117.835 | **121.917** | 66.276 | 97.455 | 73.369 |
| `ring_write` | 4.288 | 119.918 | **124.206** | 67.443 | 100.755 | 75.673 |
| `histogram_bins` | 4.519 | 128.667 | **133.186** | 67.998 | 116.369 | 84.740 |
| `prefix_scan` | 4.515 | 120.822 | **125.337** | 68.161 | 106.011 | 82.367 |
| `binary_search` | 4.681 | 119.680 | **124.361** | 67.537 | 99.961 | 81.587 |
| `sort_window` | 4.818 | 124.030 | **128.848** | 68.334 | 112.340 | 86.399 |
| `bloom_filter` | 5.532 | 122.774 | **128.306** | 69.012 | 110.975 | 82.251 |
| `hash_join` | 9.764 | 259.845 | **269.609** | 72.542 | 219.543 | 136.369 |
| `sieve` | 4.608 | 120.542 | **125.150** | 68.649 | 110.867 | 86.184 |
| `fib` | 4.119 | 119.481 | **123.600** | 67.804 | 100.270 | 72.948 |
| `collatz` | 4.329 | 122.127 | **126.456** | 68.697 | 99.686 | 76.828 |
| `matmul` | 4.854 | 120.050 | **124.904** | 67.624 | 112.559 | 100.120 |
| `json_parse` | 104.698 | 443.800 | **548.498** | 168.962 | 166.891 | 189.667 |
| `nbody` | 7.162 | 141.312 | **148.474** | 72.122 | 138.244 | 111.790 |

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
