# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-20T10:04:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366628 KiB |
| Commit | `706c05918619c10121ef72cc5cbdb7cd53b07ec7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44715261340 |
| NURL | `v0.92.1-117-g706c0591` |
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
| _(floor: empty program)_ | _2.962_ | _2.818_ | _2.981_ | _21.806_ | _10.969_ |
| `lcg` | **31.783** | 31.884 | 32.099 | 1169.318 | 2875.498 |
| `packet_classifier` | 44.586 | **43.575** | 43.829 | 137.072 | 2453.204 |
| `ring_write` | 32.543 | **32.108** | 32.279 | 56.072 | 3621.952 |
| `histogram_bins` | 31.499 | **31.178** | 31.392 | 56.766 | 3155.583 |
| `prefix_scan` | 18.038 | **17.838** | 18.276 | 50.122 | 2296.744 |
| `binary_search` | **16.812** | 17.127 | 17.374 | 75.087 | 3911.578 |
| `sort_window` | 23.242 | **22.703** | 22.912 | 142.373 | 6753.993 |
| `bloom_filter` | 11.361 | 11.295 | **11.254** | 1688.168 | 4053.574 |
| `hash_join` | **18.056** | 18.263 | 20.933 | 1990.422 | 4441.774 |
| `sieve` | 17.824 | **17.306** | 17.318 | 53.986 | 1771.901 |
| `fib` | **21.224** | 21.285 | 21.539 | 81.072 | 565.104 |
| `collatz` | **10.738** | 10.990 | 11.331 | 43.920 | 374.156 |
| `matmul` | **22.732** | 22.793 | 23.970 | 58.035 | 1656.610 |
| `json_parse` | **5.540** | 9.182 | 13.187 | 29.149 | 24.905 |
| `nbody` | **18.966** | 30.722 | 20.076 | 66.150 | 1431.481 |
| `safe_record_array` | 54.053 | **43.792** | 48.120 | n/a | n/a |
| `payload_state_machine` | 66.973 | 67.145 | **64.588** | n/a | n/a |
| `captured_closure_queue` | **78.990** | 81.255 | 85.449 | n/a | n/a |
| `dynamic_method_mix` | 105.730 | 102.067 | **101.163** | n/a | n/a |
| `csv_table_pipeline` | **61.631** | 71.662 | 62.213 | n/a | n/a |
| `chacha20` | **5.277** | 20.725 | 24.112 | n/a | n/a |
| `poly1305` | **8.841** | 17.913 | 17.711 | n/a | n/a |
| `blake2b` | **26.630** | 45.989 | 51.461 | n/a | n/a |
| `sha512` | **32.226** | 32.587 | 35.629 | n/a | n/a |
| `x25519` | **22.041** | 33.449 | 34.394 | n/a | n/a |

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
| _(floor: empty program)_ | _5.702_ | _59.930_ | _**65.632**_ | _28.437_ | _35.818_ | _58.630_ |
| `lcg` | 5.796 | 62.691 | **68.487** | 26.366 | 42.484 | 62.761 |
| `packet_classifier` | 5.974 | 65.212 | **71.186** | 27.372 | 42.628 | 63.529 |
| `ring_write` | 11.955 | 71.639 | **83.594** | 34.535 | 47.030 | 67.607 |
| `histogram_bins` | 10.616 | 66.600 | **77.216** | 31.972 | 56.322 | 69.252 |
| `prefix_scan` | 10.426 | 62.823 | **73.249** | 30.940 | 44.535 | 64.482 |
| `binary_search` | 10.644 | 66.116 | **76.760** | 31.839 | 43.827 | 66.743 |
| `sort_window` | 10.969 | 66.314 | **77.283** | 31.949 | 48.840 | 70.532 |
| `bloom_filter` | 12.359 | 74.227 | **86.586** | 35.844 | 49.330 | 75.730 |
| `hash_join` | 13.340 | 109.421 | **122.761** | 34.653 | 90.441 | 96.213 |
| `sieve` | 11.701 | 68.350 | **80.051** | 33.676 | 50.652 | 71.783 |
| `fib` | 6.541 | 67.058 | **73.599** | 27.771 | 41.417 | 64.343 |
| `collatz` | 6.147 | 63.238 | **69.385** | 27.659 | 42.500 | 61.512 |
| `matmul` | 11.201 | 66.259 | **77.460** | 32.114 | 50.437 | 80.301 |
| `json_parse` | 33.462 | 161.762 | **195.224** | 57.354 | 73.487 | 137.814 |
| `nbody` | 12.390 | 74.699 | **87.089** | 35.257 | 63.889 | 88.971 |
| `safe_record_array` | 14.867 | 143.208 | **158.075** | 35.846 | 51.051 | 83.479 |
| `payload_state_machine` | 19.768 | 121.047 | **140.815** | 41.535 | 54.295 | 97.256 |
| `captured_closure_queue` | 16.545 | 168.447 | **184.992** | 37.806 | 57.660 | 106.813 |
| `dynamic_method_mix` | 14.967 | 158.170 | **173.137** | 36.362 | 56.017 | 98.246 |
| `csv_table_pipeline` | 57.655 | 338.106 | **395.761** | 79.366 | 138.126 | 204.566 |
| `chacha20` | 43.743 | 286.420 | **330.163** | 66.364 | 64.817 | 100.620 |
| `poly1305` | 36.544 | 185.801 | **222.345** | 58.644 | 67.929 | 111.643 |
| `blake2b` | 25.728 | 158.248 | **183.976** | 47.168 | 67.349 | 105.721 |
| `sha512` | 24.451 | 206.326 | **230.777** | 45.072 | 64.829 | 96.368 |
| `x25519` | 33.276 | 681.107 | **714.383** | 54.749 | 581.108 | 341.798 |

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
