# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-22T08:51:51Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `96732834433c1660b09f20695552fd825eda8891` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32563198912 |
| NURL | `v0.48.0-6-g96732834` |
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
| _(floor: empty program)_ | _1.432_ | _1.385_ | _1.618_ | _21.431_ | _16.779_ |
| `lcg` | **38.959** | 38.976 | 39.173 | 2054.750 | 5222.133 |
| `packet_classifier` | 56.094 | **56.079** | 56.390 | 162.871 | 4525.877 |
| `ring_write` | **42.054** | 42.240 | 42.302 | 65.197 | 6251.420 |
| `histogram_bins` | **39.369** | 40.472 | 39.655 | 65.634 | 6272.196 |
| `prefix_scan` | 21.551 | **21.522** | 21.627 | 65.746 | 4451.817 |
| `binary_search` | **35.978** | 38.253 | 36.883 | 106.719 | 6663.645 |
| `sort_window` | 26.522 | **26.464** | 26.693 | 196.723 | 12487.621 |
| `bloom_filter` | 17.757 | **17.749** | 18.297 | 2829.631 | 7579.002 |
| `hash_join` | **26.915** | 27.991 | 29.271 | 3404.416 | 8105.087 |
| `sieve` | 18.575 | 18.006 | **17.903** | 66.300 | 3220.841 |
| `fib` | **25.054** | 29.724 | 25.176 | 131.451 | 1350.221 |
| `collatz` | 12.211 | **12.105** | 12.349 | 48.736 | 710.724 |
| `matmul` | **33.344** | 33.347 | 33.550 | 74.373 | 3118.088 |
| `json_parse` | 8.773 | **8.462** | 11.477 | 35.004 | 37.154 |
| `nbody` | 25.018 | 39.764 | **23.978** | 98.986 | 3029.324 |

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
| _(floor: empty program)_ | _2.630_ | _90.333_ | _**92.963**_ | _56.480_ | _76.705_ | _53.772_ |
| `lcg` | 2.724 | 93.590 | **96.314** | 56.890 | 86.191 | 58.646 |
| `packet_classifier` | 2.907 | 96.070 | **98.977** | 58.690 | 90.083 | 60.273 |
| `ring_write` | 2.876 | 94.985 | **97.861** | 57.007 | 89.252 | 60.286 |
| `histogram_bins` | 2.994 | 111.573 | **114.567** | 56.846 | 106.420 | 68.073 |
| `prefix_scan` | 3.057 | 97.449 | **100.506** | 57.592 | 95.177 | 63.342 |
| `binary_search` | 3.229 | 103.319 | **106.548** | 59.130 | 93.700 | 65.600 |
| `sort_window` | 3.269 | 103.715 | **106.984** | 56.973 | 100.717 | 70.245 |
| `bloom_filter` | 3.479 | 102.291 | **105.770** | 59.362 | 102.331 | 66.524 |
| `hash_join` | 5.918 | 252.607 | **258.525** | 60.425 | 214.413 | 112.894 |
| `sieve` | 3.026 | 96.703 | **99.729** | 57.501 | 99.691 | 69.594 |
| `fib` | 2.761 | 92.562 | **95.323** | 56.970 | 86.601 | 57.414 |
| `collatz` | 2.888 | 95.720 | **98.608** | 57.738 | 89.673 | 61.452 |
| `matmul` | 3.334 | 98.228 | **101.562** | 58.269 | 104.480 | 83.170 |
| `json_parse` | 52.875 | 427.935 | **480.810** | 109.207 | 157.191 | 163.635 |
| `nbody` | 4.623 | 122.651 | **127.274** | 58.041 | 124.776 | 90.755 |

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
