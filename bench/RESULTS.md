# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-14T09:02:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ee7cbfc554137e06fcf787a15d2050ac69d0a165` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43578154643 |
| NURL | `v0.91.1-120-gee7cbfc5` |
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
| _(floor: empty program)_ | _2.992_ | _2.873_ | _3.092_ | _23.336_ | _12.196_ |
| `lcg` | 36.095 | **36.039** | 36.181 | 1454.794 | 4019.894 |
| `packet_classifier` | 51.227 | **51.144** | 51.313 | 127.845 | 3346.695 |
| `ring_write` | 38.801 | **38.734** | 38.822 | 60.368 | 4981.877 |
| `histogram_bins` | 36.366 | **36.348** | 36.599 | 62.410 | 4392.323 |
| `prefix_scan` | 20.779 | **20.694** | 20.850 | 57.894 | 3233.375 |
| `binary_search` | 34.069 | 33.961 | **30.336** | 89.797 | 5113.455 |
| `sort_window` | 25.133 | **25.036** | 25.190 | 128.202 | 8377.275 |
| `bloom_filter` | **15.169** | 16.359 | 17.893 | 2118.981 | 5839.622 |
| `hash_join` | 22.814 | **22.674** | 25.158 | 2652.130 | 5725.016 |
| `sieve` | **20.346** | 23.399 | 20.574 | 63.032 | 2508.940 |
| `fib` | 27.592 | 27.534 | **23.558** | 117.360 | 873.484 |
| `collatz` | 12.398 | **12.308** | 12.485 | 44.354 | 571.226 |
| `matmul` | 37.145 | 37.758 | **37.129** | 63.858 | 2376.222 |
| `json_parse` | **6.397** | 10.649 | 14.913 | 33.239 | 28.035 |
| `nbody` | **21.965** | 40.846 | 22.591 | 77.154 | 2451.321 |
| `safe_record_array` | 55.626 | **48.668** | 56.860 | n/a | n/a |
| `payload_state_machine` | 66.536 | 64.598 | **64.403** | n/a | n/a |
| `captured_closure_queue` | 77.217 | **75.249** | 88.553 | n/a | n/a |
| `dynamic_method_mix` | 106.420 | **101.911** | 125.407 | n/a | n/a |
| `csv_table_pipeline` | **71.755** | 81.891 | 73.271 | n/a | n/a |
| `chacha20` | **6.406** | 34.583 | 29.596 | n/a | n/a |
| `poly1305` | **12.727** | 20.071 | 20.406 | n/a | n/a |
| `blake2b` | **38.863** | 57.092 | 63.007 | n/a | n/a |
| `sha512` | 40.732 | **40.281** | 46.638 | n/a | n/a |
| `x25519` | **30.540** | 44.405 | 45.133 | n/a | n/a |

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
| _(floor: empty program)_ | _6.032_ | _60.703_ | _**66.735**_ | _27.809_ | _35.307_ | _48.215_ |
| `lcg` | 6.240 | 67.015 | **73.255** | 27.616 | 41.008 | 52.588 |
| `packet_classifier` | 6.315 | 66.149 | **72.464** | 27.614 | 41.977 | 53.946 |
| `ring_write` | 11.981 | 67.819 | **79.800** | 33.411 | 42.418 | 55.078 |
| `histogram_bins` | 11.992 | 68.533 | **80.525** | 33.519 | 59.613 | 60.928 |
| `prefix_scan` | 12.147 | 68.842 | **80.989** | 33.645 | 45.339 | 57.447 |
| `binary_search` | 12.008 | 67.830 | **79.838** | 33.677 | 43.270 | 58.831 |
| `sort_window` | 12.277 | 68.911 | **81.188** | 33.859 | 49.915 | 63.072 |
| `bloom_filter` | 12.808 | 69.712 | **82.520** | 34.051 | 46.596 | 59.753 |
| `hash_join` | 15.551 | 117.904 | **133.455** | 36.978 | 94.846 | 95.609 |
| `sieve` | 12.396 | 68.736 | **81.132** | 34.069 | 49.461 | 64.362 |
| `fib` | 6.776 | 68.447 | **75.223** | 28.936 | 41.595 | 54.123 |
| `collatz` | 6.653 | 68.163 | **74.816** | 28.360 | 42.315 | 54.018 |
| `matmul` | 12.544 | 69.264 | **81.808** | 33.993 | 50.573 | 71.429 |
| `json_parse` | 39.191 | 171.148 | **210.339** | 60.995 | 76.590 | 133.787 |
| `nbody` | 13.668 | 72.793 | **86.461** | 35.069 | 61.543 | 83.118 |
| `safe_record_array` | 15.706 | 151.913 | **167.619** | 37.720 | 51.671 | 74.299 |
| `payload_state_machine` | 22.926 | 124.828 | **147.754** | 44.830 | 54.140 | 78.437 |
| `captured_closure_queue` | 18.123 | 175.366 | **193.489** | 39.973 | 60.301 | 97.926 |
| `dynamic_method_mix` | 17.749 | 173.773 | **191.522** | 40.033 | 58.949 | 92.615 |
| `csv_table_pipeline` | 69.917 | 378.331 | **448.248** | 92.870 | 150.326 | 210.842 |
| `chacha20` | 55.362 | 333.661 | **389.023** | 78.026 | 69.690 | 94.556 |
| `poly1305` | 45.346 | 201.229 | **246.575** | 67.228 | 71.024 | 104.088 |
| `blake2b` | 29.745 | 171.649 | **201.394** | 52.466 | 69.282 | 101.628 |
| `sha512` | 28.927 | 238.750 | **267.677** | 51.038 | 68.380 | 89.623 |
| `x25519` | 41.988 | 821.514 | **863.502** | 64.683 | 734.596 | 397.518 |

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
