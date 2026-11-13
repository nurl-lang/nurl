# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-13T09:34:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `f3cd031dd4b6555f07894ef4af86376e4ec4ca6c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43401657833 |
| NURL | `v0.91.1-90-gf3cd031d` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |
| Node | v24.22.2 |
| Python | Python 3.14.4 |

| Setting | Value |
|---|---|
| NURL flags | `nurlc` → LLVM IR; `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` (ThinLTO backend at O3 — the standard `nurl.sh` release pipeline) |
| C flags | `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` — the identical pipeline, so neither column gets a backend the other lacks |
| Rust flags | `rustc -C opt-level=3` — rustc has no prelink/backend split; opt-level 3 is the `cargo build --release` default |
| Node / Python | `node` / `python3`, no flags |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |
| Workload scale | ×1 — the published contract (`--scale N` / `BENCH_SCALE=N` multiplies it) |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so a row's cells are timings of the
same computation. **Bold** is the fastest cell in the row; `n/a` is a
language the row is not implemented in (bench/manifest.tsv).

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.768_ | _2.726_ | _2.894_ | _30.361_ | _10.853_ |
| `lcg` | 30.348 | 29.504 | **29.347** | 1114.951 | 2711.178 |
| `packet_classifier` | 42.839 | **42.457** | 43.012 | 129.733 | 2330.067 |
| `ring_write` | 31.201 | **29.714** | 30.733 | 51.783 | 3403.739 |
| `histogram_bins` | 30.233 | **29.818** | 29.894 | 52.646 | 3000.180 |
| `prefix_scan` | 17.207 | **17.195** | 17.386 | 47.921 | 2230.565 |
| `binary_search` | 15.977 | **15.587** | 16.205 | 70.436 | 3652.747 |
| `sort_window` | 21.809 | **21.474** | 21.877 | 134.837 | 6387.986 |
| `bloom_filter` | 10.058 | **9.926** | 10.073 | 1550.365 | 3876.893 |
| `hash_join` | 17.741 | **17.737** | 20.442 | 1864.550 | 4079.477 |
| `sieve` | 16.148 | **16.110** | 16.369 | 51.325 | 1720.354 |
| `fib` | 19.941 | **19.791** | 20.322 | 74.907 | 531.747 |
| `collatz` | **12.355** | 12.670 | 12.748 | 43.049 | 403.598 |
| `matmul` | 26.871 | **25.787** | 26.997 | 63.717 | 1933.875 |
| `json_parse` | **6.210** | 10.019 | 14.063 | 34.220 | 27.627 |
| `nbody` | **21.694** | 35.022 | 23.329 | 74.175 | 1681.713 |
| `safe_record_array` | 54.804 | **48.622** | 54.853 | n/a | n/a |
| `payload_state_machine` | 84.212 | 77.260 | **74.328** | n/a | n/a |
| `captured_closure_queue` | 98.320 | **93.579** | 100.481 | n/a | n/a |
| `dynamic_method_mix` | 116.596 | **115.128** | 115.400 | n/a | n/a |
| `csv_table_pipeline` | 69.770 | 79.342 | **69.310** | n/a | n/a |
| `chacha20` | **6.267** | 24.085 | 25.178 | n/a | n/a |
| `poly1305` | **9.550** | 20.150 | 20.420 | n/a | n/a |
| `blake2b` | **33.269** | 52.658 | 58.224 | n/a | n/a |
| `sha512` | **36.849** | 37.976 | 40.850 | n/a | n/a |
| `x25519` | **25.672** | 38.205 | 39.161 | n/a | n/a |

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
| _(floor: empty program)_ | _5.687_ | _56.238_ | _**61.925**_ | _26.222_ | _33.283_ | _46.024_ |
| `lcg` | 5.637 | 59.992 | **65.629** | 25.626 | 39.532 | 49.683 |
| `packet_classifier` | 5.840 | 61.452 | **67.292** | 25.756 | 39.788 | 50.254 |
| `ring_write` | 10.149 | 63.371 | **73.520** | 29.384 | 40.508 | 50.379 |
| `histogram_bins` | 9.871 | 61.644 | **71.515** | 30.065 | 53.270 | 55.241 |
| `prefix_scan` | 9.743 | 59.353 | **69.096** | 28.694 | 41.758 | 53.133 |
| `binary_search` | 9.839 | 60.297 | **70.136** | 29.749 | 40.393 | 51.514 |
| `sort_window` | 9.849 | 59.204 | **69.053** | 28.710 | 43.542 | 54.996 |
| `bloom_filter` | 10.160 | 59.289 | **69.449** | 29.353 | 42.388 | 52.679 |
| `hash_join` | 12.205 | 98.865 | **111.070** | 31.946 | 80.620 | 82.877 |
| `sieve` | 9.762 | 59.311 | **69.073** | 28.881 | 44.587 | 56.873 |
| `fib` | 5.767 | 58.523 | **64.290** | 25.161 | 38.638 | 49.217 |
| `collatz` | 6.543 | 66.387 | **72.930** | 27.675 | 41.986 | 55.211 |
| `matmul` | 11.347 | 69.248 | **80.595** | 33.761 | 51.449 | 76.370 |
| `json_parse` | 36.818 | 172.878 | **209.696** | 60.821 | 83.177 | 147.303 |
| `nbody` | 13.199 | 76.847 | **90.046** | 36.679 | 66.918 | 87.245 |
| `safe_record_array` | 14.355 | 122.375 | **136.730** | 37.732 | 55.790 | 81.145 |
| `payload_state_machine` | 22.541 | 103.997 | **126.538** | 46.677 | 60.542 | 85.594 |
| `captured_closure_queue` | 18.092 | 165.297 | **183.389** | 42.371 | 64.366 | 104.928 |
| `dynamic_method_mix` | 17.286 | 154.605 | **171.891** | 40.687 | 62.075 | 96.451 |
| `csv_table_pipeline` | 65.275 | 380.632 | **445.907** | 88.513 | 154.051 | 215.221 |
| `chacha20` | 47.276 | 340.064 | **387.340** | 71.180 | 74.185 | 99.779 |
| `poly1305` | 42.138 | 213.039 | **255.177** | 65.723 | 75.362 | 111.102 |
| `blake2b` | 27.688 | 177.046 | **204.734** | 51.305 | 74.139 | 108.124 |
| `sha512` | 27.824 | 244.363 | **272.187** | 52.153 | 76.490 | 98.392 |
| `x25519` | 40.173 | 767.005 | **807.178** | 64.498 | 677.888 | 384.290 |

## 3. Correctness gate

Each row is timed only when all of its implementations print the same
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
| `safe_record_array` | `7272179836431339923` | identical across 3 languages |
| `payload_state_machine` | `7410019181044824385` | identical across 3 languages |
| `captured_closure_queue` | `1139091110298229923` | identical across 3 languages |
| `dynamic_method_mix` | `1376727108579200197` | identical across 3 languages |
| `csv_table_pipeline` | `4173891341820504351` | identical across 3 languages |
| `chacha20` | `3720502699256473595` | identical across 3 languages |
| `poly1305` | `2498856793803813402` | identical across 3 languages |
| `blake2b` | `8590291023788228918` | identical across 3 languages |
| `sha512` | `7091519178481951668` | identical across 3 languages |
| `x25519` | `6127485567278337128` | identical across 3 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Nine of the original fifteen benchmarks are defined over 64-bit unsigned integers.
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
* `chacha20`, `poly1305`, `blake2b`, `sha512` and `x25519` are NURL / C /
  Rust only. Their NURL file is a driver around the standard library's own
  implementation (stdlib/std/chacha20poly1305.nu, hash_blake2b.nu,
  hash_sha512.nu, x25519.nu) — the row measures the stdlib a NURL program
  actually gets. C and Rust, whose standard libraries have none of the
  five, carry the same formulation written out by hand: Poly1305 at
  radix 2^64 and the donna-c64 X25519 field at radix 2^51, both with
  native 128-bit products. ChaCha20 is the one deliberate difference: C
  and Rust run the scalar RFC rounds, while the stdlib runs it on `v128`
  lanes (`v256` lanes in its x86-64-v3 clone). Each source names its
  RFC/FIPS test vector; x25519 at x1 reproduces RFC 7748's 1000-iteration
  value.
* `safe_record_array`, `payload_state_machine`, `captured_closure_queue`,
  `dynamic_method_mix` and `csv_table_pipeline` are NURL / C / Rust only.
  Each measures one language mechanism — by-value records in a checked
  Vec, payload-bearing enums and results, the closure ABI, trait-object
  dispatch, and the stdlib CSVTable parser with its zero-copy views — and
  is written in safe NURL (no `unsafe`). C spells closures and trait
  objects as the { code, environment } pairs they lower to, and carries
  the CSVTable layout by hand; see bench/README.md for what differs.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
