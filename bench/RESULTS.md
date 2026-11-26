# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-26T10:56:44Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `b59cfc869077fe9a25dd04c780803404d753b46b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45805042204 |
| NURL | `v0.95.0-4-gb59cfc869` |
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
| _(floor: empty program)_ | _2.779_ | _2.701_ | _2.847_ | _21.548_ | _11.145_ |
| `lcg` | 31.003 | **30.925** | 31.080 | 1168.532 | 2813.421 |
| `packet_classifier` | 45.091 | **44.553** | 44.761 | 136.524 | 2456.614 |
| `ring_write` | **29.825** | 30.890 | 31.342 | 53.254 | 3446.254 |
| `histogram_bins` | 30.977 | **30.908** | 31.184 | 54.736 | 3150.542 |
| `prefix_scan` | **18.051** | 18.138 | 18.452 | 49.226 | 2257.540 |
| `binary_search` | 16.673 | **16.329** | 16.733 | 71.542 | 3458.019 |
| `sort_window` | 22.346 | **22.038** | 22.339 | 139.222 | 6945.401 |
| `bloom_filter` | 10.606 | **10.593** | 10.735 | 1647.075 | 4179.788 |
| `hash_join` | **17.467** | 17.576 | 19.905 | 1957.229 | 4235.141 |
| `sieve` | 16.502 | **16.435** | 16.506 | 51.208 | 1705.290 |
| `fib` | 21.085 | **20.919** | 21.279 | 79.128 | 569.072 |
| `collatz` | **11.059** | 11.134 | 11.110 | 39.175 | 379.427 |
| `matmul` | 23.308 | 23.506 | **22.354** | 53.116 | 1711.767 |
| `json_parse` | **5.374** | 8.810 | 12.305 | 26.344 | 22.982 |
| `nbody` | **18.362** | 29.856 | 19.015 | 60.859 | 1429.168 |
| `safe_record_array` | 47.240 | **41.666** | 46.411 | n/a | n/a |
| `payload_state_machine` | 65.967 | 65.813 | **64.278** | n/a | n/a |
| `captured_closure_queue` | **78.103** | 81.746 | 86.102 | n/a | n/a |
| `dynamic_method_mix` | 99.440 | 98.269 | **98.020** | n/a | n/a |
| `csv_table_pipeline` | 61.080 | 65.268 | **57.818** | n/a | n/a |
| `chacha20` | **4.986** | 20.096 | 20.962 | n/a | n/a |
| `poly1305` | **8.013** | 17.011 | 17.370 | n/a | n/a |
| `blake2b` | **26.754** | 45.486 | 52.126 | n/a | n/a |
| `sha512` | 30.902 | **30.748** | 33.614 | n/a | n/a |
| `x25519` | **21.383** | 31.626 | 32.401 | n/a | n/a |

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
| _(floor: empty program)_ | _5.296_ | _60.535_ | _**65.831**_ | _26.410_ | _36.688_ | _61.681_ |
| `lcg` | 5.425 | 61.829 | **67.254** | 26.209 | 38.797 | 63.633 |
| `packet_classifier` | 5.601 | 65.177 | **70.778** | 26.429 | 43.317 | 61.637 |
| `ring_write` | 9.439 | 61.213 | **70.652** | 29.456 | 42.160 | 60.120 |
| `histogram_bins` | 9.931 | 65.085 | **75.016** | 31.850 | 55.970 | 67.701 |
| `prefix_scan` | 10.165 | 66.502 | **76.667** | 30.909 | 45.237 | 67.652 |
| `binary_search` | 9.965 | 64.555 | **74.520** | 30.657 | 42.916 | 65.353 |
| `sort_window` | 9.768 | 63.737 | **73.505** | 29.938 | 46.480 | 68.944 |
| `bloom_filter` | 10.164 | 64.392 | **74.556** | 30.622 | 47.475 | 67.534 |
| `hash_join` | 12.111 | 103.899 | **116.010** | 32.577 | 85.502 | 100.339 |
| `sieve` | 9.542 | 62.115 | **71.657** | 29.753 | 46.854 | 69.724 |
| `fib` | 5.650 | 62.200 | **67.850** | 26.401 | 39.884 | 60.235 |
| `collatz` | 5.613 | 65.613 | **71.226** | 26.202 | 41.096 | 60.499 |
| `matmul` | 9.777 | 62.555 | **72.332** | 30.156 | 48.345 | 75.354 |
| `json_parse` | 30.938 | 166.540 | **197.478** | 52.100 | 70.982 | 138.003 |
| `nbody` | 10.698 | 65.693 | **76.391** | 31.172 | 59.719 | 86.478 |
| `safe_record_array` | 12.180 | 135.440 | **147.620** | 32.759 | 48.263 | 79.840 |
| `payload_state_machine` | 18.078 | 113.116 | **131.194** | 38.552 | 50.941 | 83.934 |
| `captured_closure_queue` | 15.021 | 159.305 | **174.326** | 35.069 | 55.582 | 100.835 |
| `dynamic_method_mix` | 14.276 | 154.943 | **169.219** | 34.736 | 54.543 | 95.405 |
| `csv_table_pipeline` | 51.592 | 332.300 | **383.892** | 72.420 | 133.529 | 192.857 |
| `chacha20` | 37.872 | 286.767 | **324.639** | 57.643 | 65.312 | 92.642 |
| `poly1305` | 33.476 | 175.535 | **209.011** | 54.380 | 65.294 | 103.221 |
| `blake2b` | 22.802 | 153.447 | **176.249** | 43.856 | 65.521 | 105.318 |
| `sha512` | 22.481 | 201.535 | **224.016** | 42.369 | 61.673 | 91.087 |
| `x25519` | 30.770 | 615.327 | **646.097** | 50.316 | 545.711 | 335.615 |

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
