# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-18T10:12:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `c1c251132a1b40c9c722f03ffa08c44cf6a6b850` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44282126117 |
| NURL | `v0.92.1-53-gc1c25113` |
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
| _(floor: empty program)_ | _2.997_ | _2.939_ | _3.144_ | _24.512_ | _12.691_ |
| `lcg` | **36.160** | 36.163 | 36.374 | 1480.660 | 4197.286 |
| `packet_classifier` | **51.260** | 51.324 | 51.488 | 128.463 | 3365.399 |
| `ring_write` | 39.031 | **38.917** | 39.068 | 60.553 | 5090.136 |
| `histogram_bins` | 36.830 | **36.753** | 37.028 | 64.460 | 4420.561 |
| `prefix_scan` | **20.829** | 20.851 | 20.933 | 58.654 | 3232.769 |
| `binary_search` | 34.169 | 34.025 | **30.319** | 90.872 | 4915.398 |
| `sort_window` | 25.168 | **25.047** | 25.220 | 129.302 | 8255.527 |
| `bloom_filter` | **15.301** | 16.307 | 18.094 | 2103.460 | 5701.830 |
| `hash_join` | **22.859** | 22.905 | 25.333 | 2598.774 | 5636.151 |
| `sieve` | 21.748 | 24.347 | **21.061** | 64.560 | 2613.287 |
| `fib` | 28.084 | 28.085 | **24.305** | 118.370 | 865.790 |
| `collatz` | 12.771 | **12.731** | 12.949 | 47.532 | 557.105 |
| `matmul` | **37.762** | 38.443 | 38.049 | 63.208 | 2346.770 |
| `json_parse` | **6.783** | 10.902 | 15.333 | 35.222 | 29.642 |
| `nbody` | **22.280** | 41.458 | 23.033 | 79.154 | 2520.156 |
| `safe_record_array` | 50.223 | **48.809** | 56.815 | n/a | n/a |
| `payload_state_machine` | 66.598 | 64.762 | **64.630** | n/a | n/a |
| `captured_closure_queue` | 77.518 | **75.460** | 88.904 | n/a | n/a |
| `dynamic_method_mix` | 106.227 | **101.869** | 125.432 | n/a | n/a |
| `csv_table_pipeline` | **71.505** | 82.409 | 73.998 | n/a | n/a |
| `chacha20` | **6.463** | 34.382 | 29.598 | n/a | n/a |
| `poly1305` | **12.913** | 20.503 | 20.860 | n/a | n/a |
| `blake2b` | **39.211** | 57.208 | 62.896 | n/a | n/a |
| `sha512` | 41.092 | **40.673** | 44.637 | n/a | n/a |
| `x25519` | **30.864** | 44.645 | 45.477 | n/a | n/a |

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
| _(floor: empty program)_ | _6.179_ | _62.236_ | _**68.415**_ | _28.320_ | _37.515_ | _50.044_ |
| `lcg` | 6.408 | 66.816 | **73.224** | 35.527 | 41.655 | 53.257 |
| `packet_classifier` | 6.711 | 68.373 | **75.084** | 28.636 | 42.920 | 54.124 |
| `ring_write` | 12.160 | 69.513 | **81.673** | 34.091 | 43.317 | 54.972 |
| `histogram_bins` | 12.358 | 70.010 | **82.368** | 34.291 | 61.231 | 62.880 |
| `prefix_scan` | 12.201 | 69.364 | **81.565** | 33.782 | 46.651 | 58.376 |
| `binary_search` | 12.248 | 68.360 | **80.608** | 33.867 | 43.623 | 59.160 |
| `sort_window` | 12.507 | 70.674 | **83.181** | 34.291 | 49.820 | 63.376 |
| `bloom_filter` | 12.995 | 71.172 | **84.167** | 34.859 | 47.193 | 62.667 |
| `hash_join` | 16.116 | 122.985 | **139.101** | 38.450 | 97.585 | 96.670 |
| `sieve` | 12.925 | 74.324 | **87.249** | 36.106 | 52.482 | 67.851 |
| `fib` | 7.008 | 74.550 | **81.558** | 31.176 | 45.952 | 56.862 |
| `collatz` | 6.978 | 72.843 | **79.821** | 30.009 | 44.929 | 56.609 |
| `matmul` | 13.070 | 74.247 | **87.317** | 35.789 | 54.386 | 73.328 |
| `json_parse` | 40.050 | 176.388 | **216.438** | 62.971 | 78.910 | 138.026 |
| `nbody` | 14.320 | 75.503 | **89.823** | 36.997 | 63.735 | 86.121 |
| `safe_record_array` | 15.320 | 151.433 | **166.753** | 37.731 | 53.275 | 75.736 |
| `payload_state_machine` | 23.113 | 125.736 | **148.849** | 45.542 | 54.891 | 79.689 |
| `captured_closure_queue` | 18.778 | 178.881 | **197.659** | 41.707 | 61.827 | 99.556 |
| `dynamic_method_mix` | 18.212 | 175.813 | **194.025** | 40.725 | 60.122 | 93.951 |
| `csv_table_pipeline` | 69.613 | 379.212 | **448.825** | 92.341 | 150.228 | 212.580 |
| `chacha20` | 54.857 | 333.710 | **388.567** | 77.873 | 69.678 | 94.791 |
| `poly1305` | 46.215 | 205.605 | **251.820** | 68.898 | 73.342 | 107.005 |
| `blake2b` | 30.594 | 176.163 | **206.757** | 53.440 | 70.983 | 106.501 |
| `sha512` | 29.585 | 241.178 | **270.763** | 52.729 | 70.873 | 94.186 |
| `x25519` | 43.751 | 837.753 | **881.504** | 67.556 | 744.363 | 399.619 |

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
