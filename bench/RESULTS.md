# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-30T06:23:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `56a97e29586f455d3352bdce6332d31038073c38` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33296641250 |
| NURL | `v0.56.0-4-g56a97e29` |
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
| _(floor: empty program)_ | _1.097_ | _1.066_ | _1.209_ | _20.389_ | _13.589_ |
| `lcg` | **34.846** | 34.911 | 34.964 | 1374.338 | 3739.100 |
| `packet_classifier` | 59.436 | **58.722** | 59.647 | 146.948 | 3210.095 |
| `ring_write` | **38.352** | 38.355 | 38.641 | 57.154 | 4390.604 |
| `histogram_bins` | 35.897 | **35.721** | 35.896 | 59.653 | 4385.067 |
| `prefix_scan` | **19.195** | 19.217 | 19.598 | 57.837 | 3399.144 |
| `binary_search` | 34.283 | 27.593 | **26.284** | 96.853 | 4941.773 |
| `sort_window` | **34.218** | 34.321 | 35.200 | 158.312 | 8362.011 |
| `bloom_filter` | 12.290 | **12.239** | 12.560 | 2114.146 | 5674.414 |
| `hash_join` | **20.453** | 21.827 | 22.035 | 2629.976 | 6085.125 |
| `sieve` | 32.026 | 32.037 | **31.832** | 74.134 | 2274.465 |
| `fib` | 25.182 | 26.301 | **25.074** | 98.301 | 778.804 |
| `collatz` | **12.917** | 13.097 | 13.679 | 51.445 | 490.212 |
| `matmul` | **16.892** | 17.381 | 17.567 | 63.243 | 2292.940 |
| `json_parse` | 6.715 | **6.491** | 8.231 | 26.687 | 27.828 |
| `nbody` | **19.275** | 27.310 | 19.293 | 71.061 | 1985.253 |

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
| _(floor: empty program)_ | _2.047_ | _64.332_ | _**66.379**_ | _42.207_ | _51.706_ | _53.137_ |
| `lcg` | 2.173 | 72.795 | **74.968** | 40.132 | 57.225 | 59.011 |
| `packet_classifier` | 2.316 | 74.803 | **77.119** | 40.997 | 60.523 | 56.101 |
| `ring_write` | 2.404 | 76.030 | **78.434** | 41.857 | 59.690 | 57.688 |
| `histogram_bins` | 2.436 | 82.245 | **84.681** | 41.370 | 75.217 | 64.240 |
| `prefix_scan` | 2.396 | 75.609 | **78.005** | 40.977 | 64.084 | 59.423 |
| `binary_search` | 2.635 | 75.503 | **78.138** | 40.603 | 60.568 | 62.114 |
| `sort_window` | 2.622 | 79.476 | **82.098** | 41.823 | 69.471 | 67.017 |
| `bloom_filter` | 2.937 | 80.833 | **83.770** | 43.102 | 67.173 | 62.279 |
| `hash_join` | 4.952 | 187.962 | **192.914** | 46.458 | 155.190 | 106.592 |
| `sieve` | 2.461 | 76.724 | **79.185** | 40.501 | 67.295 | 66.326 |
| `fib` | 2.321 | 73.486 | **75.807** | 40.781 | 56.684 | 55.079 |
| `collatz` | 2.465 | 75.977 | **78.442** | 40.999 | 58.009 | 57.288 |
| `matmul` | 2.625 | 75.313 | **77.938** | 41.001 | 69.036 | 77.580 |
| `json_parse` | 43.573 | 323.429 | **367.002** | 87.189 | 114.749 | 156.820 |
| `nbody` | 3.581 | 91.634 | **95.215** | 42.519 | 87.422 | 85.035 |

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
