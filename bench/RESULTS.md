# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-11T19:33:19Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16365624 KiB |
| Commit | `0dcd56fda5bc7db63ec5091cad37d65e8f03b9c5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43087403266 |
| NURL | `v0.91.1` |
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
| _(floor: empty program)_ | _2.375_ | _2.364_ | _2.452_ | _22.448_ | _11.565_ |
| `lcg` | 36.522 | **36.119** | 36.382 | 1217.760 | 3656.782 |
| `packet_classifier` | 61.588 | 61.146 | **60.724** | 152.020 | 2901.606 |
| `ring_write` | 40.058 | **39.585** | 40.021 | 61.456 | 4348.694 |
| `histogram_bins` | 37.353 | **37.215** | 37.444 | 61.662 | 4187.480 |
| `prefix_scan` | 20.773 | **20.696** | 20.808 | 58.944 | 2873.472 |
| `binary_search` | 35.706 | **35.130** | 36.688 | 100.370 | 4838.621 |
| `sort_window` | **35.594** | 35.973 | 36.527 | 159.550 | 8290.787 |
| `bloom_filter` | 13.728 | **13.534** | 13.706 | 2087.656 | 5311.533 |
| `hash_join` | 21.989 | **21.431** | 23.330 | 2614.329 | 5727.676 |
| `sieve` | 36.518 | 37.833 | **35.669** | 77.289 | 2299.443 |
| `fib` | 26.921 | 26.766 | **26.694** | 101.766 | 734.707 |
| `collatz` | 15.090 | **14.837** | 14.980 | 53.825 | 488.368 |
| `matmul` | **18.819** | 18.827 | 18.948 | 59.043 | 2036.254 |
| `json_parse` | **5.841** | 9.122 | 12.020 | 30.568 | 26.952 |
| `nbody` | 21.294 | 31.184 | **21.041** | 69.846 | 1921.198 |
| `safe_record_array` | 60.911 | **53.844** | 57.452 | n/a | n/a |
| `payload_state_machine` | 85.715 | **72.954** | 74.180 | n/a | n/a |
| `captured_closure_queue` | 83.766 | **79.696** | 98.404 | n/a | n/a |
| `dynamic_method_mix` | 107.877 | 104.868 | **103.827** | n/a | n/a |
| `csv_table_pipeline` | **72.234** | 79.804 | 80.168 | n/a | n/a |
| `chacha20` | **5.385** | 30.562 | 28.744 | n/a | n/a |
| `poly1305` | **10.019** | 21.049 | 21.273 | n/a | n/a |
| `blake2b` | **38.716** | 42.710 | 48.073 | n/a | n/a |
| `sha512` | 37.480 | **36.697** | 40.348 | n/a | n/a |
| `x25519` | **26.308** | 37.970 | 37.667 | n/a | n/a |

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
| _(floor: empty program)_ | _5.133_ | _51.660_ | _**56.793**_ | _20.777_ | _25.922_ | _50.523_ |
| `lcg` | 4.830 | 58.187 | **63.017** | 21.494 | 30.681 | 56.513 |
| `packet_classifier` | 5.132 | 60.127 | **65.259** | 21.637 | 31.441 | 55.111 |
| `ring_write` | 12.882 | 61.338 | **74.220** | 29.036 | 34.084 | 58.185 |
| `histogram_bins` | 12.471 | 61.439 | **73.910** | 29.052 | 52.388 | 61.076 |
| `prefix_scan` | 12.274 | 60.493 | **72.767** | 28.269 | 34.293 | 57.711 |
| `binary_search` | 12.552 | 59.397 | **71.949** | 28.700 | 32.381 | 58.991 |
| `sort_window` | 12.715 | 61.891 | **74.606** | 28.944 | 37.777 | 63.157 |
| `bloom_filter` | 13.502 | 62.733 | **76.235** | 30.350 | 35.304 | 60.230 |
| `hash_join` | 15.911 | 110.855 | **126.766** | 32.146 | 85.170 | 100.499 |
| `sieve` | 12.544 | 60.711 | **73.255** | 28.123 | 36.525 | 64.649 |
| `fib` | 5.179 | 59.322 | **64.501** | 21.704 | 31.891 | 54.001 |
| `collatz` | 5.297 | 59.398 | **64.695** | 21.502 | 31.249 | 53.872 |
| `matmul` | 13.037 | 61.468 | **74.505** | 29.686 | 39.453 | 72.664 |
| `json_parse` | 39.646 | 171.453 | **211.099** | 57.812 | 70.743 | 148.028 |
| `nbody` | 14.159 | 67.070 | **81.229** | 30.607 | 51.101 | 87.714 |
| `safe_record_array` | 16.182 | 117.260 | **133.442** | 33.935 | 40.993 | 78.466 |
| `payload_state_machine` | 23.070 | 93.590 | **116.660** | 39.893 | 43.152 | 81.994 |
| `captured_closure_queue` | 19.056 | 159.912 | **178.968** | 37.254 | 49.385 | 104.898 |
| `dynamic_method_mix` | 18.025 | 151.404 | **169.429** | 34.515 | 46.130 | 94.567 |
| `csv_table_pipeline` | 71.599 | 423.514 | **495.113** | 91.418 | 155.028 | 231.970 |
| `chacha20` | 53.397 | 364.913 | **418.310** | 72.915 | 63.000 | 101.128 |
| `poly1305` | 44.570 | 211.843 | **256.413** | 63.769 | 62.600 | 111.074 |
| `blake2b` | 30.486 | 178.622 | **209.108** | 49.996 | 60.290 | 107.631 |
| `sha512` | 29.578 | 251.090 | **280.668** | 47.974 | 60.289 | 94.553 |
| `x25519` | 40.869 | 910.594 | **951.463** | 61.523 | 781.789 | 444.427 |

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
