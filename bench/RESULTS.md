# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-25T20:13:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `87a68d4b722f389130b692c7d3eb20e2371f295c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45691902745 |
| NURL | `v0.95.0` |
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
| _(floor: empty program)_ | _2.975_ | _2.836_ | _3.046_ | _21.656_ | _11.524_ |
| `lcg` | **31.483** | 31.601 | 31.758 | 1158.463 | 2812.797 |
| `packet_classifier` | 48.992 | **44.486** | 44.544 | 132.171 | 2410.993 |
| `ring_write` | **31.552** | 31.597 | 31.686 | 55.307 | 3476.647 |
| `histogram_bins` | 31.005 | **30.891** | 30.952 | 54.049 | 3184.999 |
| `prefix_scan` | 18.037 | **17.837** | 17.995 | 49.508 | 2249.383 |
| `binary_search` | 16.745 | **16.152** | 17.595 | 73.559 | 3679.417 |
| `sort_window` | 22.339 | 22.175 | **22.160** | 134.714 | 6526.309 |
| `bloom_filter` | **10.730** | 10.741 | 10.810 | 1621.213 | 4105.036 |
| `hash_join` | **17.551** | 18.022 | 20.159 | 1960.122 | 4241.949 |
| `sieve` | 17.485 | 17.541 | **17.073** | 53.531 | 1683.025 |
| `fib` | 21.780 | **21.693** | 22.119 | 82.105 | 551.635 |
| `collatz` | 11.545 | **11.429** | 11.695 | 42.526 | 400.040 |
| `matmul` | **22.608** | 23.133 | 23.121 | 55.137 | 1559.936 |
| `json_parse` | **5.708** | 9.318 | 13.239 | 30.751 | 25.976 |
| `nbody` | **18.649** | 30.018 | 19.424 | 63.936 | 1400.096 |
| `safe_record_array` | 47.432 | **41.974** | 46.825 | n/a | n/a |
| `payload_state_machine` | 65.329 | **63.101** | 63.483 | n/a | n/a |
| `captured_closure_queue` | **75.769** | 78.795 | 84.252 | n/a | n/a |
| `dynamic_method_mix` | 101.903 | 101.566 | **101.533** | n/a | n/a |
| `csv_table_pipeline` | 62.449 | 72.270 | **61.732** | n/a | n/a |
| `chacha20` | **4.974** | 19.393 | 20.782 | n/a | n/a |
| `poly1305` | **7.896** | 17.206 | 17.781 | n/a | n/a |
| `blake2b` | **27.405** | 46.211 | 50.456 | n/a | n/a |
| `sha512` | 31.681 | **31.517** | 33.840 | n/a | n/a |
| `x25519` | **21.042** | 32.283 | 33.666 | n/a | n/a |

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
| _(floor: empty program)_ | _5.564_ | _61.832_ | _**67.396**_ | _27.320_ | _36.662_ | _66.838_ |
| `lcg` | 5.489 | 63.693 | **69.182** | 26.424 | 52.303 | 62.007 |
| `packet_classifier` | 5.461 | 64.531 | **69.992** | 26.563 | 42.867 | 63.705 |
| `ring_write` | 9.798 | 64.936 | **74.734** | 30.875 | 42.963 | 63.332 |
| `histogram_bins` | 9.505 | 65.766 | **75.271** | 30.316 | 56.370 | 71.502 |
| `prefix_scan` | 9.576 | 64.520 | **74.096** | 30.179 | 45.167 | 65.736 |
| `binary_search` | 10.579 | 67.357 | **77.936** | 32.208 | 44.091 | 67.148 |
| `sort_window` | 10.223 | 68.447 | **78.670** | 31.723 | 50.270 | 71.501 |
| `bloom_filter` | 9.992 | 65.084 | **75.076** | 30.327 | 45.979 | 67.967 |
| `hash_join` | 12.445 | 104.045 | **116.490** | 32.992 | 88.470 | 103.899 |
| `sieve` | 10.018 | 69.068 | **79.086** | 31.462 | 50.152 | 73.404 |
| `fib` | 6.093 | 67.430 | **73.523** | 27.521 | 43.415 | 65.104 |
| `collatz` | 6.052 | 68.115 | **74.167** | 27.830 | 43.887 | 65.905 |
| `matmul` | 10.605 | 68.933 | **79.538** | 32.207 | 51.860 | 81.909 |
| `json_parse` | 32.444 | 171.793 | **204.237** | 53.893 | 74.671 | 147.379 |
| `nbody` | 11.628 | 77.537 | **89.165** | 33.711 | 61.211 | 89.562 |
| `safe_record_array` | 13.189 | 144.489 | **157.678** | 34.215 | 52.425 | 94.243 |
| `payload_state_machine` | 18.794 | 118.498 | **137.292** | 40.750 | 53.540 | 87.733 |
| `captured_closure_queue` | 15.595 | 168.321 | **183.916** | 37.327 | 58.264 | 107.754 |
| `dynamic_method_mix` | 14.827 | 166.548 | **181.375** | 35.911 | 57.531 | 100.123 |
| `csv_table_pipeline` | 57.656 | 352.812 | **410.468** | 79.372 | 138.055 | 210.189 |
| `chacha20` | 40.972 | 307.899 | **348.871** | 62.094 | 64.237 | 98.075 |
| `poly1305` | 34.246 | 184.666 | **218.912** | 56.400 | 67.469 | 106.497 |
| `blake2b` | 24.341 | 163.611 | **187.952** | 46.470 | 67.558 | 112.453 |
| `sha512` | 23.186 | 213.581 | **236.767** | 44.705 | 66.251 | 103.450 |
| `x25519` | 31.922 | 654.157 | **686.079** | 53.923 | 581.388 | 336.276 |

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
