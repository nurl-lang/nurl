# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-14T04:47:10Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `ede65cf52ce96593ff73d62343a11d24a1a5081d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43557786771 |
| NURL | `v0.91.1-118-gede65cf5` |
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
| _(floor: empty program)_ | _3.543_ | _3.526_ | _3.766_ | _28.565_ | _15.988_ |
| `lcg` | 41.612 | **41.414** | 41.710 | 1823.943 | 4957.066 |
| `packet_classifier` | 58.709 | **58.484** | 58.967 | 167.089 | 4141.630 |
| `ring_write` | 44.745 | **44.601** | 44.880 | 73.971 | 6259.070 |
| `histogram_bins` | 41.970 | 43.000 | **41.644** | 72.592 | 5660.681 |
| `prefix_scan` | **23.860** | 24.123 | 24.107 | 67.933 | 4277.410 |
| `binary_search` | 41.849 | 41.749 | **37.771** | 110.532 | 6375.590 |
| `sort_window` | **28.826** | 29.029 | 29.202 | 198.426 | 12043.735 |
| `bloom_filter` | **18.098** | 19.888 | 20.522 | 2775.490 | 7198.995 |
| `hash_join` | 29.234 | **28.992** | 31.905 | 3433.199 | 7753.545 |
| `sieve` | **24.629** | 28.596 | 25.114 | 73.248 | 3175.681 |
| `fib` | 32.136 | 31.973 | **27.557** | 136.251 | 1094.094 |
| `collatz` | 14.410 | **14.307** | 14.448 | 53.889 | 692.098 |
| `matmul` | **35.976** | 35.984 | 36.351 | 75.497 | 3061.918 |
| `json_parse` | **8.175** | 13.392 | 18.848 | 40.096 | 38.275 |
| `nbody` | **26.694** | 49.053 | 27.618 | 103.389 | 2943.856 |
| `safe_record_array` | 64.346 | **57.574** | 65.980 | n/a | n/a |
| `payload_state_machine` | 77.278 | **73.342** | 75.550 | n/a | n/a |
| `captured_closure_queue` | 90.804 | **87.593** | 104.084 | n/a | n/a |
| `dynamic_method_mix` | 122.889 | **117.322** | 151.742 | n/a | n/a |
| `csv_table_pipeline` | **85.120** | 95.393 | 87.089 | n/a | n/a |
| `chacha20` | **9.655** | 41.262 | 33.642 | n/a | n/a |
| `poly1305` | **13.993** | 23.463 | 23.773 | n/a | n/a |
| `blake2b` | **43.661** | 66.885 | 71.755 | n/a | n/a |
| `sha512` | **49.001** | 49.137 | 51.711 | n/a | n/a |
| `x25519` | **36.016** | 51.382 | 52.561 | n/a | n/a |

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
| _(floor: empty program)_ | _7.169_ | _73.577_ | _**80.746**_ | _32.200_ | _41.139_ | _57.419_ |
| `lcg` | 7.364 | 80.728 | **88.092** | 32.284 | 49.017 | 62.921 |
| `packet_classifier` | 7.425 | 80.261 | **87.686** | 32.157 | 49.107 | 63.067 |
| `ring_write` | 15.039 | 83.610 | **98.649** | 40.286 | 50.984 | 64.178 |
| `histogram_bins` | 15.104 | 85.557 | **100.661** | 40.806 | 73.690 | 73.159 |
| `prefix_scan` | 15.000 | 83.002 | **98.002** | 40.272 | 53.789 | 67.781 |
| `binary_search` | 15.101 | 83.737 | **98.838** | 40.347 | 50.875 | 69.882 |
| `sort_window` | 15.151 | 84.251 | **99.402** | 40.326 | 57.076 | 74.430 |
| `bloom_filter` | 15.378 | 81.452 | **96.830** | 39.663 | 54.098 | 69.756 |
| `hash_join` | 19.355 | 153.302 | **172.657** | 44.027 | 119.143 | 116.340 |
| `sieve` | 15.008 | 81.990 | **96.998** | 39.763 | 60.061 | 84.259 |
| `fib` | 7.576 | 80.441 | **88.017** | 32.402 | 49.238 | 63.280 |
| `collatz` | 7.581 | 80.685 | **88.266** | 32.472 | 50.629 | 64.433 |
| `matmul` | 15.357 | 83.713 | **99.070** | 40.297 | 60.259 | 86.292 |
| `json_parse` | 50.355 | 214.673 | **265.028** | 77.290 | 92.228 | 164.397 |
| `nbody` | 16.869 | 87.912 | **104.781** | 41.615 | 73.665 | 100.651 |
| `safe_record_array` | 18.528 | 186.785 | **205.313** | 44.205 | 60.180 | 88.764 |
| `payload_state_machine` | 28.916 | 152.006 | **180.922** | 54.281 | 64.340 | 93.592 |
| `captured_closure_queue` | 22.623 | 220.072 | **242.695** | 48.493 | 71.880 | 118.883 |
| `dynamic_method_mix` | 22.153 | 216.350 | **238.503** | 48.014 | 68.867 | 115.541 |
| `csv_table_pipeline` | 90.301 | 476.782 | **567.083** | 116.223 | 182.485 | 261.824 |
| `chacha20` | 72.876 | 412.621 | **485.497** | 99.204 | 80.688 | 111.957 |
| `poly1305` | 60.079 | 252.755 | **312.834** | 86.830 | 85.067 | 127.332 |
| `blake2b` | 38.072 | 208.551 | **246.623** | 64.487 | 80.489 | 121.517 |
| `sha512` | 37.030 | 302.597 | **339.627** | 62.978 | 80.723 | 108.116 |
| `x25519` | 54.300 | 1059.763 | **1114.063** | 79.684 | 953.528 | 505.158 |

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
