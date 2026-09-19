# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-19T13:40:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c7a2bf52d8c8168ab23cd0661884a20e0789570b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/35446242657 |
| NURL | `v0.66.0-7-gc7a2bf52` |
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
| _(floor: empty program)_ | _1.492_ | _1.470_ | _1.713_ | _23.598_ | _17.436_ |
| `lcg` | **39.020** | 39.032 | 39.232 | 2056.272 | 5224.144 |
| `packet_classifier` | **56.112** | 56.134 | 56.382 | 161.977 | 4327.329 |
| `ring_write` | 42.190 | **42.169** | 42.338 | 67.296 | 6282.116 |
| `histogram_bins` | **39.566** | 40.553 | 39.709 | 66.592 | 6219.659 |
| `prefix_scan` | 21.725 | **21.683** | 21.781 | 64.170 | 4452.488 |
| `binary_search` | 39.476 | 38.098 | **37.004** | 105.967 | 5967.243 |
| `sort_window` | **26.501** | 26.581 | 26.810 | 197.843 | 11533.971 |
| `bloom_filter` | **16.654** | 17.829 | 18.370 | 2866.494 | 7869.621 |
| `hash_join` | **27.215** | 28.273 | 29.400 | 3449.784 | 8689.364 |
| `sieve` | 20.729 | **20.205** | 20.930 | 69.541 | 3747.773 |
| `fib` | 25.736 | 30.657 | **25.716** | 131.379 | 1391.441 |
| `collatz` | **12.266** | 12.357 | 12.483 | 51.918 | 731.385 |
| `matmul` | 33.443 | **33.192** | 33.362 | 78.233 | 3245.489 |
| `json_parse` | 10.044 | **9.003** | 11.769 | 36.044 | 39.033 |
| `nbody` | 25.150 | 39.662 | **24.124** | 102.231 | 3081.159 |

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
| _(floor: empty program)_ | _3.365_ | _98.383_ | _**101.748**_ | _60.446_ | _79.582_ | _62.284_ |
| `lcg` | 3.552 | 109.482 | **113.034** | 60.302 | 90.495 | 70.756 |
| `packet_classifier` | 3.654 | 111.111 | **114.765** | 60.651 | 93.271 | 72.592 |
| `ring_write` | 3.845 | 110.011 | **113.856** | 60.313 | 91.766 | 72.141 |
| `histogram_bins` | 4.010 | 121.037 | **125.047** | 62.452 | 111.736 | 80.795 |
| `prefix_scan` | 4.030 | 110.771 | **114.801** | 60.803 | 97.068 | 74.948 |
| `binary_search` | 4.203 | 108.773 | **112.976** | 59.880 | 92.288 | 76.408 |
| `sort_window` | 4.407 | 112.329 | **116.736** | 61.005 | 104.902 | 82.473 |
| `bloom_filter` | 4.753 | 113.730 | **118.483** | 61.348 | 102.865 | 76.613 |
| `hash_join` | 9.364 | 259.161 | **268.525** | 66.202 | 220.451 | 126.354 |
| `sieve` | 4.020 | 110.372 | **114.392** | 60.595 | 103.472 | 82.878 |
| `fib` | 3.532 | 108.815 | **112.347** | 60.058 | 89.852 | 68.862 |
| `collatz` | 3.984 | 112.512 | **116.496** | 61.320 | 92.897 | 73.650 |
| `matmul` | 4.653 | 115.967 | **120.620** | 64.165 | 110.453 | 95.585 |
| `json_parse` | 103.485 | 478.256 | **581.741** | 162.978 | 163.695 | 180.594 |
| `nbody` | 6.672 | 129.635 | **136.307** | 63.969 | 130.966 | 104.303 |

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
