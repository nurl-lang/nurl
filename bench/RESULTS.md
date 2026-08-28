# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-28T03:24:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `660cb505a6d6306ff544363c7682e5be2c4e645e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33138550539 |
| NURL | `v0.54.0` |
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
| _(floor: empty program)_ | _1.551_ | _1.536_ | _1.754_ | _26.595_ | _17.558_ |
| `lcg` | 44.082 | **44.040** | 44.246 | 1815.892 | 5328.435 |
| `packet_classifier` | 63.498 | **63.454** | 63.590 | 158.103 | 4516.495 |
| `ring_write` | **47.578** | **47.578** | 47.749 | 72.469 | 6688.989 |
| `histogram_bins` | **44.556** | **44.556** | 44.684 | 74.758 | 7150.591 |
| `prefix_scan` | 24.450 | **24.336** | 24.628 | 70.944 | 4828.266 |
| `binary_search` | **34.065** | 35.676 | 36.484 | 109.278 | 6441.340 |
| `sort_window` | 29.923 | **29.908** | 30.165 | 165.680 | 12366.703 |
| `bloom_filter` | 19.656 | **18.646** | 20.741 | 2716.214 | 7807.639 |
| `hash_join` | **27.710** | 28.695 | 30.123 | 3427.793 | 8830.024 |
| `sieve` | 20.266 | **19.942** | 20.092 | 71.015 | 3594.636 |
| `fib` | **27.792** | 33.041 | 27.949 | 141.230 | 1286.019 |
| `collatz` | 13.665 | **13.570** | 13.778 | 53.088 | 802.861 |
| `matmul` | **46.281** | 46.286 | 46.536 | 82.592 | 3559.348 |
| `json_parse` | **8.572** | 8.761 | 12.102 | 38.143 | 38.161 |
| `nbody` | 26.655 | 44.858 | **26.201** | 99.033 | 3281.436 |

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
| _(floor: empty program)_ | _2.941_ | _101.132_ | _**104.073**_ | _62.608_ | _83.378_ | _64.746_ |
| `lcg` | 3.074 | 100.609 | **103.683** | 62.210 | 93.275 | 71.692 |
| `packet_classifier` | 3.190 | 100.770 | **103.960** | 62.967 | 94.767 | 72.509 |
| `ring_write` | 3.247 | 101.715 | **104.962** | 62.684 | 96.133 | 74.421 |
| `histogram_bins` | 3.423 | 118.918 | **122.341** | 63.265 | 112.941 | 82.421 |
| `prefix_scan` | 3.376 | 103.753 | **107.129** | 62.684 | 101.369 | 77.740 |
| `binary_search` | 3.524 | 108.610 | **112.134** | 63.368 | 97.581 | 79.462 |
| `sort_window` | 3.631 | 110.800 | **114.431** | 63.218 | 107.051 | 84.208 |
| `bloom_filter` | 3.843 | 107.164 | **111.007** | 63.732 | 105.401 | 80.967 |
| `hash_join` | 6.343 | 251.525 | **257.868** | 65.732 | 212.978 | 128.634 |
| `sieve` | 3.380 | 102.472 | **105.852** | 62.971 | 105.801 | 84.299 |
| `fib` | 3.071 | 100.311 | **103.382** | 62.575 | 94.181 | 71.355 |
| `collatz` | 3.232 | 103.439 | **106.671** | 63.337 | 96.713 | 74.434 |
| `matmul` | 3.623 | 106.435 | **110.058** | 63.506 | 108.868 | 97.269 |
| `json_parse` | 52.042 | 414.227 | **466.269** | 113.112 | 160.740 | 181.518 |
| `nbody` | 4.985 | 129.426 | **134.411** | 64.584 | 129.416 | 106.662 |

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
