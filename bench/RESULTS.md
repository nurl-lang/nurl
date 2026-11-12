# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-12T09:53:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16365628 KiB |
| Commit | `0d1e4d18a5122d29495aa7c5c8706da0e32c1bb1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43194574780 |
| NURL | `v0.91.1-4-g0d1e4d18` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
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
| _(floor: empty program)_ | _3.318_ | _3.417_ | _3.870_ | _30.283_ | _15.535_ |
| `lcg` | 44.276 | **44.258** | 44.424 | 1461.440 | 4371.849 |
| `packet_classifier` | 75.857 | **74.777** | 76.334 | 182.518 | 3408.453 |
| `ring_write` | 48.582 | **48.232** | 48.902 | 75.856 | 5127.218 |
| `histogram_bins` | **45.351** | 45.353 | 45.526 | 76.998 | 4818.395 |
| `prefix_scan` | **25.611** | 25.612 | 25.930 | 71.843 | 3439.374 |
| `binary_search` | 43.383 | **43.025** | 45.147 | 123.136 | 5348.560 |
| `sort_window` | **43.498** | 43.659 | 44.848 | 192.123 | 9911.263 |
| `bloom_filter` | 18.212 | **16.954** | 17.489 | 2568.735 | 6300.126 |
| `hash_join` | 27.156 | **26.550** | 28.952 | 3138.354 | 6937.439 |
| `sieve` | 43.783 | 45.770 | **43.256** | 94.571 | 2851.697 |
| `fib` | **32.789** | 32.839 | 33.020 | 124.688 | 881.147 |
| `collatz` | 18.865 | **18.792** | 18.824 | 69.045 | 585.988 |
| `matmul` | **23.078** | 23.187 | 23.742 | 74.783 | 2477.619 |
| `json_parse` | **7.403** | 11.345 | 15.421 | 39.744 | 34.033 |
| `nbody` | **25.805** | 38.205 | 25.829 | 87.581 | 2285.824 |
| `safe_record_array` | 73.771 | **65.548** | 70.027 | n/a | n/a |
| `payload_state_machine` | 103.692 | **87.703** | 89.932 | n/a | n/a |
| `captured_closure_queue` | 101.082 | **96.164** | 118.774 | n/a | n/a |
| `dynamic_method_mix` | 129.050 | 126.636 | **125.236** | n/a | n/a |
| `csv_table_pipeline` | **93.125** | 106.564 | 100.883 | n/a | n/a |
| `chacha20` | **6.733** | 37.541 | 35.421 | n/a | n/a |
| `poly1305` | **12.726** | 26.051 | 26.225 | n/a | n/a |
| `blake2b` | **46.920** | 51.284 | 57.557 | n/a | n/a |
| `sha512` | 46.057 | **44.946** | 49.406 | n/a | n/a |
| `x25519` | **31.952** | 46.103 | 45.818 | n/a | n/a |

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
| _(floor: empty program)_ | _6.936_ | _71.137_ | _**78.073**_ | _30.394_ | _38.407_ | _66.351_ |
| `lcg` | 7.138 | 78.483 | **85.621** | 30.422 | 45.343 | 70.290 |
| `packet_classifier` | 7.048 | 79.379 | **86.427** | 30.047 | 45.574 | 71.062 |
| `ring_write` | 13.953 | 81.149 | **95.102** | 36.765 | 46.347 | 73.413 |
| `histogram_bins` | 14.326 | 81.992 | **96.318** | 37.813 | 70.676 | 81.407 |
| `prefix_scan` | 14.314 | 80.978 | **95.292** | 37.239 | 50.077 | 77.303 |
| `binary_search` | 14.405 | 81.750 | **96.155** | 37.666 | 47.717 | 78.902 |
| `sort_window` | 14.719 | 83.196 | **97.915** | 38.135 | 55.303 | 84.189 |
| `bloom_filter` | 15.191 | 82.916 | **98.107** | 38.206 | 52.614 | 79.127 |
| `hash_join` | 18.131 | 141.688 | **159.819** | 41.369 | 112.441 | 126.288 |
| `sieve` | 13.798 | 78.351 | **92.149** | 36.126 | 52.048 | 82.881 |
| `fib` | 6.858 | 75.545 | **82.403** | 29.202 | 44.299 | 69.299 |
| `collatz` | 7.041 | 78.386 | **85.427** | 29.823 | 44.739 | 70.518 |
| `matmul` | 14.593 | 81.429 | **96.022** | 37.720 | 56.256 | 95.122 |
| `json_parse` | 46.287 | 209.778 | **256.065** | 69.380 | 90.180 | 180.559 |
| `nbody` | 15.927 | 86.046 | **101.973** | 38.912 | 71.220 | 112.891 |
| `safe_record_array` | 17.353 | 143.956 | **161.309** | 40.544 | 56.801 | 99.978 |
| `payload_state_machine` | 27.142 | 118.480 | **145.622** | 50.377 | 59.767 | 104.849 |
| `captured_closure_queue` | 21.510 | 196.699 | **218.209** | 45.064 | 68.247 | 132.744 |
| `dynamic_method_mix` | 20.911 | 194.176 | **215.087** | 44.179 | 64.959 | 123.887 |
| `csv_table_pipeline` | 82.838 | 508.891 | **591.729** | 106.726 | 186.032 | 287.137 |
| `chacha20` | 63.861 | 442.977 | **506.838** | 87.218 | 78.329 | 123.385 |
| `poly1305` | 52.590 | 256.830 | **309.420** | 75.750 | 81.974 | 138.535 |
| `blake2b` | 34.781 | 215.952 | **250.733** | 58.079 | 78.152 | 132.896 |
| `sha512` | 33.475 | 306.504 | **339.979** | 56.219 | 78.323 | 118.965 |
| `x25519` | 48.022 | 1067.744 | **1115.766** | 71.295 | 936.983 | 532.239 |

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
