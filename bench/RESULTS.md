# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-24T12:32:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `20fecb0ed6dfd13f40bcb8c1da3293547444dc9e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45393398583 |
| NURL | `v0.94.0-78-g20fecb0ed` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |
| Node | v24.22.3 |
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
| _(floor: empty program)_ | _3.349_ | _3.307_ | _3.514_ | _26.610_ | _14.844_ |
| `lcg` | 41.362 | **41.007** | 41.138 | 1783.526 | 4888.569 |
| `packet_classifier` | 58.098 | **57.960** | 58.235 | 165.834 | 4016.272 |
| `ring_write` | 44.158 | **43.935** | 44.178 | 69.185 | 6301.067 |
| `histogram_bins` | 41.634 | 42.466 | **41.062** | 70.846 | 5675.911 |
| `prefix_scan` | 23.573 | **23.404** | 23.645 | 66.465 | 4283.441 |
| `binary_search` | 41.378 | 41.258 | **37.160** | 109.980 | 5856.792 |
| `sort_window` | 28.481 | **28.413** | 28.912 | 198.954 | 12389.249 |
| `bloom_filter` | **17.253** | 19.326 | 20.164 | 2789.151 | 7296.682 |
| `hash_join` | 28.402 | **28.308** | 31.140 | 3343.837 | 7807.998 |
| `sieve` | 23.562 | 27.301 | **23.556** | 72.198 | 3192.486 |
| `fib` | 31.797 | 31.650 | **27.230** | 133.644 | 1107.185 |
| `collatz` | 14.123 | **14.046** | 14.234 | 53.108 | 704.914 |
| `matmul` | 35.265 | **35.241** | 35.504 | 73.938 | 2795.067 |
| `json_parse` | **7.955** | 13.288 | 18.213 | 39.741 | 36.435 |
| `nbody` | **26.043** | 48.425 | 27.246 | 101.791 | 2949.230 |
| `safe_record_array` | 58.513 | **56.916** | 65.235 | n/a | n/a |
| `payload_state_machine` | 77.256 | **72.825** | 75.010 | n/a | n/a |
| `captured_closure_queue` | 92.742 | **86.897** | 103.549 | n/a | n/a |
| `dynamic_method_mix` | 140.192 | **117.837** | 149.466 | n/a | n/a |
| `csv_table_pipeline` | **83.908** | 94.779 | 86.009 | n/a | n/a |
| `chacha20` | **9.422** | 40.613 | 33.142 | n/a | n/a |
| `poly1305` | **13.413** | 22.846 | 22.930 | n/a | n/a |
| `blake2b` | **44.045** | 66.369 | 71.051 | n/a | n/a |
| `sha512` | **48.478** | 48.696 | 51.356 | n/a | n/a |
| `x25519` | **35.383** | 50.560 | 51.798 | n/a | n/a |

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
| _(floor: empty program)_ | _6.178_ | _70.600_ | _**76.778**_ | _30.727_ | _39.921_ | _63.911_ |
| `lcg` | 6.356 | 76.393 | **82.749** | 30.448 | 46.219 | 73.554 |
| `packet_classifier` | 6.554 | 77.051 | **83.605** | 33.522 | 47.201 | 70.476 |
| `ring_write` | 13.095 | 79.041 | **92.136** | 36.902 | 47.745 | 72.424 |
| `histogram_bins` | 13.138 | 82.281 | **95.419** | 37.023 | 70.788 | 79.709 |
| `prefix_scan` | 13.325 | 80.097 | **93.422** | 37.421 | 51.055 | 81.701 |
| `binary_search` | 13.349 | 78.960 | **92.309** | 37.515 | 48.881 | 79.350 |
| `sort_window` | 13.594 | 80.936 | **94.530** | 37.744 | 55.230 | 84.353 |
| `bloom_filter` | 14.387 | 81.643 | **96.030** | 38.263 | 53.651 | 79.377 |
| `hash_join` | 17.635 | 144.079 | **161.714** | 41.860 | 117.100 | 125.023 |
| `sieve` | 13.511 | 79.618 | **93.129** | 37.537 | 55.955 | 84.996 |
| `fib` | 6.544 | 77.224 | **83.768** | 30.715 | 46.852 | 72.057 |
| `collatz` | 6.660 | 78.153 | **84.813** | 30.843 | 49.184 | 72.419 |
| `matmul` | 13.972 | 79.859 | **93.831** | 37.983 | 57.995 | 94.395 |
| `json_parse` | 47.014 | 220.474 | **267.488** | 71.926 | 90.036 | 176.369 |
| `nbody` | 15.404 | 85.829 | **101.233** | 39.635 | 72.039 | 108.446 |
| `safe_record_array` | 16.894 | 180.258 | **197.152** | 41.666 | 57.806 | 98.056 |
| `payload_state_machine` | 26.439 | 148.129 | **174.568** | 50.568 | 60.928 | 104.378 |
| `captured_closure_queue` | 21.440 | 214.453 | **235.893** | 45.999 | 69.478 | 129.276 |
| `dynamic_method_mix` | 20.779 | 210.510 | **231.289** | 45.857 | 67.920 | 123.753 |
| `csv_table_pipeline` | 84.393 | 485.896 | **570.289** | 109.885 | 182.117 | 266.617 |
| `chacha20` | 68.635 | 439.254 | **507.889** | 93.160 | 78.939 | 122.013 |
| `poly1305` | 56.383 | 248.113 | **304.496** | 81.433 | 83.706 | 135.373 |
| `blake2b` | 34.994 | 205.479 | **240.473** | 59.456 | 78.734 | 130.897 |
| `sha512` | 33.804 | 297.789 | **331.593** | 58.181 | 78.230 | 117.390 |
| `x25519` | 51.390 | 1058.848 | **1110.238** | 76.038 | 945.024 | 509.973 |

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
