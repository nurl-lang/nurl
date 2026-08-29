# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T11:43:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `e5e348416db5513782b09365fe5dd4b711943e3e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33250625485 |
| NURL | `v0.55.0-5-ge5e34841` |
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
| _(floor: empty program)_ | _1.421_ | _1.405_ | _1.612_ | _21.555_ | _16.828_ |
| `lcg` | **39.025** | 39.036 | 40.154 | 2048.553 | 5235.866 |
| `packet_classifier` | **56.076** | 56.147 | 56.266 | 161.494 | 4544.781 |
| `ring_write` | 42.175 | **42.030** | 42.196 | 64.646 | 6324.907 |
| `histogram_bins` | **39.433** | 40.508 | 39.505 | 65.944 | 6003.800 |
| `prefix_scan` | 21.658 | **21.650** | 21.651 | 63.911 | 4511.102 |
| `binary_search` | 39.441 | 38.118 | **37.000** | 105.932 | 6564.347 |
| `sort_window` | 26.549 | **26.498** | 26.697 | 195.376 | 11455.334 |
| `bloom_filter` | 17.800 | **17.739** | 18.301 | 2861.217 | 7618.764 |
| `hash_join` | **26.761** | 27.866 | 29.190 | 3435.939 | 8335.092 |
| `sieve` | 18.167 | 18.008 | **17.841** | 65.210 | 3485.026 |
| `fib` | **25.065** | 29.707 | 25.232 | 130.851 | 1344.885 |
| `collatz` | 12.185 | **12.132** | 12.301 | 48.026 | 714.425 |
| `matmul` | 33.535 | **33.240** | 33.447 | 76.179 | 3185.572 |
| `json_parse` | 8.737 | **8.526** | 11.561 | 34.956 | 36.758 |
| `nbody` | 25.134 | 39.662 | **23.931** | 97.512 | 2989.874 |

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
| _(floor: empty program)_ | _2.581_ | _91.058_ | _**93.639**_ | _55.901_ | _76.549_ | _59.688_ |
| `lcg` | 2.738 | 100.887 | **103.625** | 56.711 | 86.137 | 67.964 |
| `packet_classifier` | 2.831 | 106.029 | **108.860** | 57.275 | 89.192 | 69.557 |
| `ring_write` | 2.939 | 104.526 | **107.465** | 57.867 | 90.209 | 71.929 |
| `histogram_bins` | 3.032 | 114.405 | **117.437** | 57.186 | 106.026 | 77.212 |
| `prefix_scan` | 3.043 | 104.096 | **107.139** | 57.071 | 94.327 | 72.766 |
| `binary_search` | 3.195 | 104.350 | **107.545** | 58.022 | 90.152 | 74.287 |
| `sort_window` | 3.245 | 107.092 | **110.337** | 57.983 | 100.273 | 81.040 |
| `bloom_filter` | 3.430 | 106.670 | **110.100** | 57.100 | 98.269 | 75.252 |
| `hash_join` | 5.897 | 256.503 | **262.400** | 61.199 | 215.665 | 128.937 |
| `sieve` | 3.045 | 102.331 | **105.376** | 58.076 | 98.534 | 79.678 |
| `fib` | 2.780 | 101.584 | **104.364** | 56.509 | 87.962 | 67.723 |
| `collatz` | 2.958 | 104.900 | **107.858** | 57.043 | 89.519 | 70.604 |
| `matmul` | 3.353 | 105.248 | **108.601** | 58.191 | 102.764 | 92.296 |
| `json_parse` | 52.924 | 430.929 | **483.853** | 109.263 | 157.273 | 173.423 |
| `nbody` | 4.583 | 124.395 | **128.978** | 58.900 | 124.826 | 100.264 |

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
