# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-10T09:51:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `07f8f1603c35d4d4b077e7824c8e107976b2fd4c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42793375703 |
| NURL | `v0.90.0-80-g07f8f160` |
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
| _(floor: empty program)_ | _3.114_ | _2.997_ | _3.338_ | _28.759_ | _15.696_ |
| `lcg` | 44.101 | **43.924** | 44.103 | 1463.370 | 4202.001 |
| `packet_classifier` | 75.185 | **74.019** | 74.348 | 185.010 | 3431.653 |
| `ring_write` | 48.111 | **47.873** | 48.435 | 73.896 | 5091.438 |
| `histogram_bins` | 45.121 | **44.911** | 45.199 | 76.407 | 4802.014 |
| `prefix_scan` | **25.140** | 25.219 | 25.183 | 70.601 | 3392.175 |
| `binary_search` | 43.243 | **42.802** | 44.660 | 121.166 | 5519.489 |
| `sort_window` | **43.189** | 43.262 | 44.315 | 189.306 | 9844.241 |
| `bloom_filter` | 16.418 | **16.319** | 16.725 | 2492.832 | 6636.257 |
| `hash_join` | 26.332 | **25.773** | 28.496 | 3153.236 | 6886.652 |
| `sieve` | 43.300 | 46.006 | **42.819** | 93.662 | 2785.352 |
| `fib` | **32.297** | 32.346 | 32.516 | 123.652 | 879.343 |
| `collatz` | 18.465 | **18.395** | 18.648 | 69.160 | 587.019 |
| `matmul` | 23.752 | 23.620 | **23.516** | 74.623 | 2527.923 |
| `json_parse` | **7.294** | 11.369 | 15.130 | 39.516 | 34.365 |
| `nbody` | 25.833 | 38.031 | **25.719** | 86.586 | 2286.330 |
| `safe_record_array` | 74.212 | **65.682** | 69.780 | n/a | n/a |
| `payload_state_machine` | 103.464 | **87.636** | 90.057 | n/a | n/a |
| `captured_closure_queue` | 251.469 | **95.971** | 118.751 | n/a | n/a |
| `dynamic_method_mix` | 130.084 | 126.268 | **125.177** | n/a | n/a |
| `csv_table_pipeline` | **91.456** | 101.164 | 97.715 | n/a | n/a |
| `chacha20` | **6.551** | 37.405 | 35.206 | n/a | n/a |
| `poly1305` | **12.188** | 25.700 | 25.915 | n/a | n/a |
| `blake2b` | **46.530** | 51.430 | 57.766 | n/a | n/a |
| `sha512` | 46.097 | **44.702** | 49.211 | n/a | n/a |
| `x25519` | **31.370** | 45.731 | 45.531 | n/a | n/a |

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
| _(floor: empty program)_ | _6.597_ | _69.491_ | _**76.088**_ | _28.583_ | _36.422_ | _64.890_ |
| `lcg` | 6.819 | 78.939 | **85.758** | 30.689 | 45.194 | 68.011 |
| `packet_classifier` | 6.676 | 74.489 | **81.165** | 28.616 | 43.548 | 69.230 |
| `ring_write` | 15.341 | 75.200 | **90.541** | 36.544 | 43.788 | 70.009 |
| `histogram_bins` | 15.683 | 77.723 | **93.406** | 37.556 | 67.845 | 77.355 |
| `prefix_scan` | 15.345 | 75.589 | **90.934** | 36.576 | 46.207 | 73.478 |
| `binary_search` | 15.931 | 75.399 | **91.330** | 37.366 | 43.495 | 73.231 |
| `sort_window` | 15.739 | 76.992 | **92.731** | 37.694 | 50.387 | 79.567 |
| `bloom_filter` | 16.456 | 78.578 | **95.034** | 38.261 | 48.878 | 76.345 |
| `hash_join` | 19.299 | 138.930 | **158.229** | 41.356 | 110.073 | 124.197 |
| `sieve` | 15.800 | 76.899 | **92.699** | 37.858 | 50.915 | 82.474 |
| `fib` | 6.798 | 73.716 | **80.514** | 28.714 | 44.537 | 68.551 |
| `collatz` | 6.744 | 74.811 | **81.555** | 28.585 | 44.760 | 70.372 |
| `matmul` | 16.381 | 77.499 | **93.880** | 38.393 | 54.797 | 93.331 |
| `json_parse` | 46.556 | 209.081 | **255.637** | 68.965 | 87.878 | 178.432 |
| `nbody` | 17.610 | 83.791 | **101.401** | 40.060 | 69.219 | 106.892 |
| `safe_record_array` | 18.824 | 145.555 | **164.379** | 41.479 | 55.292 | 98.307 |
| `payload_state_machine` | 28.283 | 116.646 | **144.929** | 50.951 | 58.413 | 104.212 |
| `captured_closure_queue` | 22.654 | 158.038 | **180.692** | 45.818 | 66.817 | 130.577 |
| `dynamic_method_mix` | 21.638 | 152.388 | **174.026** | 44.317 | 61.964 | 120.959 |
| `csv_table_pipeline` | 84.016 | 502.833 | **586.849** | 107.358 | 183.730 | 284.541 |
| `chacha20` | 62.545 | 433.272 | **495.817** | 85.302 | 76.008 | 122.642 |
| `poly1305` | 52.268 | 253.156 | **305.424** | 74.833 | 80.497 | 136.061 |
| `blake2b` | 36.168 | 213.949 | **250.117** | 58.991 | 78.159 | 132.958 |
| `sha512` | 34.735 | 303.133 | **337.868** | 57.279 | 77.868 | 117.723 |
| `x25519` | 49.164 | 1052.585 | **1101.749** | 71.646 | 930.424 | 527.071 |

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
