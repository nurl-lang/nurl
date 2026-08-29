# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T08:34:51Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e9c8a85be3039432ddee64c3e5881db54c6d787c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33243299265 |
| NURL | `v0.55.0` |
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
| _(floor: empty program)_ | _1.462_ | _1.448_ | _1.672_ | _23.647_ | _18.066_ |
| `lcg` | 39.212 | **39.152** | 39.399 | 2051.683 | 5036.359 |
| `packet_classifier` | 56.414 | **56.269** | 56.496 | 162.094 | 4475.115 |
| `ring_write` | 42.380 | **42.181** | 42.477 | 66.436 | 6192.948 |
| `histogram_bins` | **39.585** | 40.797 | 39.866 | 67.490 | 6068.428 |
| `prefix_scan` | 21.833 | **21.777** | 21.864 | 66.683 | 4537.246 |
| `binary_search` | 39.562 | 38.183 | **37.127** | 108.778 | 5878.535 |
| `sort_window` | 26.810 | **26.628** | 26.913 | 199.074 | 11538.553 |
| `bloom_filter` | 17.872 | **17.855** | 18.425 | 2862.334 | 7801.836 |
| `hash_join` | **27.062** | 28.120 | 29.539 | 3461.209 | 8521.190 |
| `sieve` | 18.791 | **18.521** | 18.588 | 66.769 | 3301.791 |
| `fib` | **25.233** | 29.881 | 25.543 | 133.417 | 1352.099 |
| `collatz` | 12.256 | **12.132** | 12.343 | 49.729 | 724.696 |
| `matmul` | 33.823 | **33.602** | 33.713 | 76.479 | 3339.940 |
| `json_parse` | 8.925 | **8.689** | 11.849 | 36.702 | 38.829 |
| `nbody` | 25.150 | 39.671 | **23.984** | 100.561 | 3024.137 |

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
| _(floor: empty program)_ | _2.713_ | _98.407_ | _**101.120**_ | _61.218_ | _83.171_ | _67.427_ |
| `lcg` | 2.823 | 108.264 | **111.087** | 61.095 | 92.548 | 71.248 |
| `packet_classifier` | 2.923 | 108.109 | **111.032** | 60.461 | 92.301 | 69.949 |
| `ring_write` | 3.033 | 107.736 | **110.769** | 59.811 | 92.638 | 71.156 |
| `histogram_bins` | 3.033 | 118.896 | **121.929** | 60.637 | 110.540 | 79.426 |
| `prefix_scan` | 3.161 | 109.626 | **112.787** | 61.269 | 100.481 | 74.609 |
| `binary_search` | 3.267 | 111.975 | **115.242** | 61.434 | 94.913 | 77.218 |
| `sort_window` | 3.336 | 111.190 | **114.526** | 59.581 | 104.708 | 82.280 |
| `bloom_filter` | 3.564 | 112.714 | **116.278** | 60.627 | 105.916 | 78.382 |
| `hash_join` | 6.143 | 262.881 | **269.024** | 64.237 | 223.400 | 127.956 |
| `sieve` | 3.171 | 109.884 | **113.055** | 60.560 | 105.239 | 81.129 |
| `fib` | 2.810 | 107.237 | **110.047** | 60.091 | 92.545 | 69.388 |
| `collatz` | 3.011 | 110.672 | **113.683** | 59.562 | 93.763 | 73.115 |
| `matmul` | 3.380 | 109.855 | **113.235** | 60.914 | 108.849 | 95.414 |
| `json_parse` | 53.160 | 443.821 | **496.981** | 111.945 | 163.515 | 178.262 |
| `nbody` | 4.776 | 132.042 | **136.818** | 63.296 | 129.980 | 103.681 |

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
