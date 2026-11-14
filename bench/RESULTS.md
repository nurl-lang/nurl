# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-14T18:47:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `4a075824af453b203ebe1f3fb622f59d589c948a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43627946007 |
| NURL | `v0.92.1` |
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
| _(floor: empty program)_ | _3.180_ | _3.159_ | _3.379_ | _24.112_ | _12.943_ |
| `lcg` | 36.539 | 36.436 | **36.385** | 1457.842 | 4111.087 |
| `packet_classifier` | **51.326** | 51.437 | 51.659 | 129.722 | 3470.559 |
| `ring_write` | **38.941** | 38.957 | 39.228 | 62.699 | 5285.995 |
| `histogram_bins` | 36.621 | **36.547** | 36.863 | 63.664 | 4424.020 |
| `prefix_scan` | **20.851** | 20.925 | 21.099 | 58.103 | 3234.318 |
| `binary_search` | 34.291 | 34.182 | **30.679** | 90.412 | 5153.547 |
| `sort_window` | 25.371 | **25.269** | 25.452 | 130.000 | 8588.526 |
| `bloom_filter` | **15.366** | 16.341 | 17.836 | 2113.736 | 5985.321 |
| `hash_join` | 23.203 | **23.119** | 25.792 | 2586.757 | 5755.902 |
| `sieve` | 21.494 | 24.187 | **21.054** | 65.766 | 2536.110 |
| `fib` | 27.946 | 28.031 | **24.061** | 118.045 | 880.302 |
| `collatz` | 12.762 | **12.614** | 13.019 | 47.075 | 562.635 |
| `matmul` | 38.660 | 38.141 | **37.813** | 65.527 | 2326.262 |
| `json_parse` | **6.490** | 10.898 | 15.249 | 34.454 | 28.517 |
| `nbody` | **22.341** | 41.411 | 22.902 | 79.647 | 2485.975 |
| `safe_record_array` | 55.695 | **48.978** | 57.015 | n/a | n/a |
| `payload_state_machine` | 66.738 | **64.814** | 64.875 | n/a | n/a |
| `captured_closure_queue` | 77.491 | **75.434** | 89.014 | n/a | n/a |
| `dynamic_method_mix` | 106.507 | **102.191** | 125.279 | n/a | n/a |
| `csv_table_pipeline` | **71.941** | 82.024 | 74.498 | n/a | n/a |
| `chacha20` | **6.422** | 34.425 | 29.787 | n/a | n/a |
| `poly1305` | **12.770** | 20.356 | 20.555 | n/a | n/a |
| `blake2b` | **39.140** | 57.300 | 62.904 | n/a | n/a |
| `sha512` | 40.834 | **40.502** | 44.542 | n/a | n/a |
| `x25519` | **30.986** | 44.651 | 45.430 | n/a | n/a |

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
| _(floor: empty program)_ | _6.372_ | _62.896_ | _**69.268**_ | _28.678_ | _36.972_ | _50.314_ |
| `lcg` | 6.452 | 68.717 | **75.169** | 28.818 | 43.603 | 55.422 |
| `packet_classifier` | 6.637 | 68.500 | **75.137** | 28.415 | 43.125 | 54.394 |
| `ring_write` | 12.409 | 70.310 | **82.719** | 34.569 | 44.103 | 56.077 |
| `histogram_bins` | 12.427 | 71.819 | **84.246** | 34.644 | 61.024 | 62.301 |
| `prefix_scan` | 12.350 | 69.930 | **82.280** | 34.221 | 46.459 | 58.936 |
| `binary_search` | 12.543 | 70.399 | **82.942** | 34.467 | 45.057 | 59.959 |
| `sort_window` | 12.623 | 70.756 | **83.379** | 34.482 | 49.515 | 64.964 |
| `bloom_filter` | 13.349 | 72.932 | **86.281** | 35.693 | 49.696 | 61.240 |
| `hash_join` | 16.695 | 122.292 | **138.987** | 39.207 | 98.196 | 96.952 |
| `sieve` | 12.971 | 75.826 | **88.797** | 37.153 | 52.537 | 66.828 |
| `fib` | 6.972 | 70.511 | **77.483** | 29.667 | 44.685 | 55.752 |
| `collatz` | 6.940 | 72.451 | **79.391** | 29.612 | 45.359 | 57.041 |
| `matmul` | 13.189 | 72.673 | **85.862** | 35.529 | 52.427 | 72.775 |
| `json_parse` | 40.060 | 173.925 | **213.985** | 62.622 | 77.557 | 135.015 |
| `nbody` | 13.951 | 74.735 | **88.686** | 36.176 | 64.116 | 85.655 |
| `safe_record_array` | 15.892 | 155.579 | **171.471** | 39.160 | 54.385 | 77.284 |
| `payload_state_machine` | 23.914 | 127.576 | **151.490** | 46.570 | 56.289 | 80.348 |
| `captured_closure_queue` | 18.703 | 181.499 | **200.202** | 41.986 | 61.844 | 100.755 |
| `dynamic_method_mix` | 18.416 | 184.145 | **202.561** | 42.765 | 61.667 | 94.763 |
| `csv_table_pipeline` | 70.518 | 382.101 | **452.619** | 93.149 | 151.918 | 213.200 |
| `chacha20` | 56.223 | 336.183 | **392.406** | 78.707 | 69.470 | 94.573 |
| `poly1305` | 46.222 | 203.887 | **250.109** | 69.381 | 72.951 | 105.728 |
| `blake2b` | 30.749 | 177.036 | **207.785** | 54.438 | 71.370 | 105.357 |
| `sha512` | 29.320 | 241.265 | **270.585** | 52.512 | 70.456 | 93.341 |
| `x25519` | 43.292 | 828.806 | **872.098** | 66.594 | 742.469 | 400.192 |

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
