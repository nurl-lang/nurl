# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-21T07:18:17Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `431733634ed921b77b516ea5915eab5d281c3496` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32457730133 |
| NURL | `v0.47.0-6-g43173363` |
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
| _(floor: empty program)_ | _1.232_ | _1.201_ | _1.401_ | _19.752_ | _13.740_ |
| `lcg` | **34.142** | 34.213 | 34.271 | 1411.397 | 4092.114 |
| `packet_classifier` | **49.201** | **49.201** | 49.382 | 123.564 | 3562.991 |
| `ring_write` | **36.886** | 36.937 | 37.048 | 56.791 | 5157.150 |
| `histogram_bins` | 34.577 | **34.520** | 34.681 | 57.574 | 5330.028 |
| `prefix_scan` | **18.879** | 18.880 | 19.009 | 55.844 | 3814.756 |
| `binary_search` | **25.845** | 27.698 | 28.289 | 86.217 | 5622.164 |
| `sort_window` | **23.233** | 23.239 | 23.389 | 128.131 | 8486.579 |
| `bloom_filter` | 15.281 | **14.493** | 16.025 | 2130.006 | 6125.094 |
| `hash_join` | **21.381** | 22.134 | 23.271 | 2639.558 | 6304.789 |
| `sieve` | 15.818 | **15.443** | 15.799 | 55.866 | 2844.199 |
| `fib` | **21.584** | 25.676 | 21.752 | 110.974 | 1003.017 |
| `collatz` | 10.646 | **10.577** | 10.788 | 40.126 | 585.508 |
| `matmul` | **35.076** | 35.965 | 35.427 | 64.848 | 2840.521 |
| `json_parse` | **6.773** | 6.993 | 9.456 | 28.563 | 29.388 |
| `nbody` | 20.731 | 34.794 | **20.387** | 75.271 | 2560.461 |

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
| _(floor: empty program)_ | _2.276_ | _79.683_ | _**81.959**_ | _50.938_ | _68.423_ | _46.434_ |
| `lcg` | 2.424 | 80.457 | **82.881** | 50.384 | 76.365 | 51.859 |
| `packet_classifier` | 2.477 | 81.409 | **83.886** | 50.693 | 77.110 | 51.451 |
| `ring_write` | 2.587 | 81.247 | **83.834** | 50.426 | 78.447 | 51.995 |
| `histogram_bins` | 2.701 | 95.184 | **97.885** | 50.822 | 92.192 | 60.443 |
| `prefix_scan` | 2.739 | 83.323 | **86.062** | 50.626 | 81.713 | 54.631 |
| `binary_search` | 2.800 | 87.324 | **90.124** | 50.721 | 79.727 | 56.890 |
| `sort_window` | 2.807 | 88.648 | **91.455** | 50.675 | 87.148 | 59.964 |
| `bloom_filter` | 3.020 | 86.322 | **89.342** | 51.499 | 85.930 | 57.278 |
| `hash_join` | 4.921 | 198.167 | **203.088** | 53.060 | 169.414 | 93.956 |
| `sieve` | 2.735 | 83.405 | **86.140** | 50.944 | 85.951 | 60.083 |
| `fib` | 2.436 | 81.575 | **84.011** | 50.751 | 77.233 | 50.641 |
| `collatz` | 2.597 | 82.275 | **84.872** | 50.800 | 78.795 | 52.932 |
| `matmul` | 2.955 | 84.969 | **87.924** | 51.102 | 88.124 | 70.121 |
| `json_parse` | 40.753 | 325.359 | **366.112** | 90.308 | 128.762 | 135.146 |
| `nbody` | 3.921 | 104.217 | **108.138** | 52.034 | 103.859 | 77.313 |

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
