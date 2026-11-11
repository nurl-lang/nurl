# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-11T18:14:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366636 KiB |
| Commit | `a013bfae93c3f95925d589a5909e374b9705b502` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43074822649 |
| NURL | `v0.91.0-7-ga013bfae` |
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
| _(floor: empty program)_ | _3.379_ | _3.352_ | _3.562_ | _27.286_ | _15.183_ |
| `lcg` | 41.515 | **41.199** | 41.550 | 1823.621 | 5026.599 |
| `packet_classifier` | **58.393** | 58.500 | 58.510 | 165.985 | 4289.067 |
| `ring_write` | 44.264 | **44.222** | 44.556 | 69.518 | 6783.547 |
| `histogram_bins` | **42.092** | 43.119 | 43.296 | 71.531 | 5750.123 |
| `prefix_scan` | **23.541** | 23.610 | 23.826 | 69.319 | 4294.927 |
| `binary_search` | 41.914 | **41.794** | 43.316 | 110.589 | 5916.146 |
| `sort_window` | 28.634 | **28.494** | 28.586 | 197.407 | 12175.858 |
| `bloom_filter` | **17.843** | 19.311 | 20.160 | 2779.479 | 7221.158 |
| `hash_join` | 29.029 | **28.650** | 31.634 | 3440.689 | 7746.941 |
| `sieve` | 24.568 | 27.859 | **24.030** | 73.928 | 3113.655 |
| `fib` | 32.021 | **31.931** | 31.995 | 134.186 | 1115.917 |
| `collatz` | **14.260** | 14.379 | 14.629 | 53.149 | 692.839 |
| `matmul` | 35.336 | **35.225** | 35.626 | 74.117 | 2991.341 |
| `json_parse` | **8.288** | 13.138 | 18.138 | 38.954 | 36.764 |
| `nbody` | **26.536** | 48.857 | 27.269 | 103.599 | 2985.185 |
| `safe_record_array` | 63.800 | **57.572** | 66.066 | n/a | n/a |
| `payload_state_machine` | 87.978 | **73.186** | 76.735 | n/a | n/a |
| `captured_closure_queue` | 90.725 | **87.675** | 101.396 | n/a | n/a |
| `dynamic_method_mix` | 120.707 | **117.598** | 149.252 | n/a | n/a |
| `csv_table_pipeline` | **84.639** | 94.710 | 85.353 | n/a | n/a |
| `chacha20` | **9.512** | 40.634 | 35.725 | n/a | n/a |
| `poly1305` | **13.411** | 22.878 | 23.185 | n/a | n/a |
| `blake2b` | **46.260** | 67.143 | 70.881 | n/a | n/a |
| `sha512` | 49.820 | **49.113** | 51.826 | n/a | n/a |
| `x25519` | **35.264** | 51.320 | 51.529 | n/a | n/a |

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
| _(floor: empty program)_ | _7.463_ | _74.510_ | _**81.973**_ | _32.283_ | _41.218_ | _69.673_ |
| `lcg` | 6.975 | 78.547 | **85.522** | 31.526 | 47.415 | 70.932 |
| `packet_classifier` | 7.100 | 77.998 | **85.098** | 31.191 | 47.673 | 71.352 |
| `ring_write` | 15.625 | 80.033 | **95.658** | 39.544 | 48.439 | 73.221 |
| `histogram_bins` | 15.881 | 81.753 | **97.634** | 40.487 | 70.495 | 82.277 |
| `prefix_scan` | 15.733 | 80.041 | **95.774** | 39.840 | 51.921 | 77.078 |
| `binary_search` | 16.062 | 79.743 | **95.805** | 40.219 | 49.544 | 78.641 |
| `sort_window` | 16.231 | 82.833 | **99.064** | 40.611 | 57.002 | 83.501 |
| `bloom_filter` | 16.894 | 82.862 | **99.756** | 41.241 | 54.443 | 79.209 |
| `hash_join` | 20.292 | 146.397 | **166.689** | 45.053 | 117.349 | 127.274 |
| `sieve` | 16.133 | 80.434 | **96.567** | 40.580 | 56.214 | 84.393 |
| `fib` | 7.088 | 77.199 | **84.287** | 31.280 | 47.800 | 72.894 |
| `collatz` | 7.462 | 78.892 | **86.354** | 31.914 | 48.489 | 73.387 |
| `matmul` | 16.769 | 82.127 | **98.896** | 41.390 | 59.689 | 95.883 |
| `json_parse` | 48.280 | 201.757 | **250.037** | 73.544 | 90.664 | 175.990 |
| `nbody` | 18.090 | 87.543 | **105.633** | 42.764 | 72.896 | 112.154 |
| `safe_record_array` | 19.644 | 140.662 | **160.306** | 44.483 | 59.069 | 102.251 |
| `payload_state_machine` | 29.677 | 116.670 | **146.347** | 54.442 | 62.858 | 104.470 |
| `captured_closure_queue` | 23.350 | 185.123 | **208.473** | 48.731 | 71.239 | 132.217 |
| `dynamic_method_mix` | 22.296 | 181.232 | **203.528** | 46.941 | 67.103 | 122.834 |
| `csv_table_pipeline` | 88.171 | 479.004 | **567.175** | 113.299 | 183.219 | 274.382 |
| `chacha20` | 69.286 | 426.779 | **496.065** | 94.036 | 79.353 | 122.565 |
| `poly1305` | 58.157 | 250.262 | **308.419** | 82.836 | 83.825 | 137.123 |
| `blake2b` | 37.345 | 210.609 | **247.954** | 62.543 | 80.804 | 132.779 |
| `sha512` | 36.259 | 299.414 | **335.673** | 61.777 | 79.711 | 117.492 |
| `x25519` | 53.330 | 1050.651 | **1103.981** | 78.575 | 953.431 | 509.494 |

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
