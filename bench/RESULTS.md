# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-01T13:37:50Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `39a4ac9e7ae62b1ef8c98520f579d390cbec69fc` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36869460312 |
| NURL | `v0.68.0-3-g39a4ac9e` |
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
| _(floor: empty program)_ | _1.483_ | _1.404_ | _1.645_ | _23.982_ | _17.784_ |
| `lcg` | **39.134** | 39.269 | 39.527 | 1908.106 | 5134.751 |
| `packet_classifier` | **56.277** | 56.455 | 56.498 | 162.768 | 4356.252 |
| `ring_write` | **42.332** | 42.367 | 42.558 | 69.599 | 6433.492 |
| `histogram_bins` | **39.665** | 40.842 | 40.916 | 66.490 | 6126.397 |
| `prefix_scan` | 21.876 | **21.814** | 23.497 | 67.432 | 4491.799 |
| `binary_search` | 39.722 | **38.282** | 41.095 | 107.149 | 6514.230 |
| `sort_window` | 26.715 | **26.559** | 26.608 | 199.325 | 11879.427 |
| `bloom_filter` | **16.815** | 17.964 | 18.472 | 2833.481 | 7948.638 |
| `hash_join` | **26.935** | 28.222 | 29.421 | 3408.861 | 8430.616 |
| `sieve` | 18.839 | 18.540 | **18.393** | 66.569 | 3324.788 |
| `fib` | **25.387** | 29.914 | 30.123 | 132.759 | 1380.141 |
| `collatz` | 12.300 | **12.266** | 12.649 | 49.883 | 738.866 |
| `matmul` | 33.788 | **33.722** | 33.826 | 79.016 | 3106.796 |
| `json_parse` | 9.215 | **8.588** | 12.007 | 38.227 | 41.117 |
| `nbody` | **25.173** | 39.787 | 25.214 | 101.199 | 3178.172 |

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
| _(floor: empty program)_ | _3.552_ | _101.975_ | _**105.527**_ | _62.659_ | _80.756_ | _52.755_ |
| `lcg` | 3.728 | 112.580 | **116.308** | 62.930 | 92.113 | 58.398 |
| `packet_classifier` | 3.760 | 112.781 | **116.541** | 62.312 | 95.326 | 58.643 |
| `ring_write` | 3.931 | 113.401 | **117.332** | 62.314 | 93.947 | 59.735 |
| `histogram_bins` | 4.056 | 121.282 | **125.338** | 62.228 | 110.829 | 67.627 |
| `prefix_scan` | 4.069 | 114.950 | **119.019** | 62.050 | 98.684 | 63.828 |
| `binary_search` | 4.270 | 114.635 | **118.905** | 62.455 | 95.477 | 64.885 |
| `sort_window` | 4.462 | 116.452 | **120.914** | 62.487 | 105.222 | 70.927 |
| `bloom_filter` | 5.136 | 117.869 | **123.005** | 63.830 | 105.275 | 65.821 |
| `hash_join` | 9.296 | 265.838 | **275.134** | 68.127 | 222.568 | 112.273 |
| `sieve` | 4.164 | 114.388 | **118.552** | 63.232 | 107.161 | 69.794 |
| `fib` | 3.692 | 114.468 | **118.160** | 63.091 | 92.879 | 57.201 |
| `collatz` | 3.998 | 115.472 | **119.470** | 63.101 | 94.068 | 59.335 |
| `matmul` | 4.643 | 116.929 | **121.572** | 64.467 | 112.681 | 80.165 |
| `json_parse` | 104.851 | 471.153 | **576.004** | 164.117 | 169.266 | 158.749 |
| `nbody` | 6.829 | 133.648 | **140.477** | 68.453 | 133.524 | 95.669 |

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
