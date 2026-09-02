# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-02T08:11:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `8d2268785478c45f43665a96a78f4faac6c46369` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33606992754 |
| NURL | `v0.58.0-8-g8d226878` |
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
| _(floor: empty program)_ | _1.554_ | _1.543_ | _1.771_ | _26.618_ | _18.207_ |
| `lcg` | 44.151 | **44.064** | 44.325 | 1816.293 | 5519.258 |
| `packet_classifier` | 63.548 | **63.511** | 63.811 | 158.797 | 4476.983 |
| `ring_write` | **47.533** | 47.588 | 47.892 | 74.417 | 6573.287 |
| `histogram_bins` | **44.511** | 44.579 | 44.821 | 74.743 | 6389.424 |
| `prefix_scan` | **24.325** | 24.377 | 24.608 | 70.937 | 4988.587 |
| `binary_search` | 41.569 | **35.654** | 36.621 | 111.059 | 6643.692 |
| `sort_window` | **29.968** | 30.001 | 30.241 | 165.952 | 11883.540 |
| `bloom_filter` | 19.796 | **18.727** | 20.723 | 2771.310 | 7702.083 |
| `hash_join` | **27.663** | 28.679 | 30.253 | 3412.169 | 8399.400 |
| `sieve` | 20.677 | **20.326** | 20.454 | 72.859 | 3964.767 |
| `fib` | 28.094 | 33.145 | **28.064** | 143.461 | 1291.795 |
| `collatz` | 13.645 | **13.642** | 13.885 | 51.957 | 749.226 |
| `matmul` | 46.425 | 46.253 | **46.007** | 84.176 | 3419.320 |
| `json_parse` | 8.909 | **8.822** | 12.250 | 39.213 | 38.512 |
| `nbody` | 26.695 | 44.998 | **26.273** | 95.971 | 3291.324 |

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
| _(floor: empty program)_ | _3.022_ | _106.175_ | _**109.197**_ | _65.752_ | _89.290_ | _65.295_ |
| `lcg` | 3.100 | 114.009 | **117.109** | 64.780 | 100.084 | 95.338 |
| `packet_classifier` | 3.216 | 117.324 | **120.540** | 66.444 | 100.233 | 75.659 |
| `ring_write` | 3.335 | 113.248 | **116.583** | 63.958 | 99.233 | 75.639 |
| `histogram_bins` | 3.395 | 123.107 | **126.502** | 64.179 | 113.478 | 82.065 |
| `prefix_scan` | 3.376 | 116.326 | **119.702** | 64.105 | 102.875 | 78.644 |
| `binary_search` | 3.606 | 115.236 | **118.842** | 64.527 | 99.615 | 80.235 |
| `sort_window` | 3.656 | 117.563 | **121.219** | 64.451 | 109.788 | 85.247 |
| `bloom_filter` | 3.931 | 119.115 | **123.046** | 66.145 | 109.617 | 82.671 |
| `hash_join` | 6.633 | 262.230 | **268.863** | 70.566 | 219.060 | 135.219 |
| `sieve` | 3.441 | 116.090 | **119.531** | 65.365 | 108.791 | 85.722 |
| `fib` | 3.130 | 114.927 | **118.057** | 65.635 | 97.438 | 72.423 |
| `collatz` | 3.343 | 119.283 | **122.626** | 66.038 | 100.076 | 77.947 |
| `matmul` | 3.755 | 116.318 | **120.073** | 66.034 | 113.572 | 100.233 |
| `json_parse` | 56.407 | 440.575 | **496.982** | 119.273 | 163.340 | 186.290 |
| `nbody` | 5.080 | 135.022 | **140.102** | 66.735 | 132.349 | 108.797 |

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
