# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-13T20:32:23Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ab45d9db114a58fdab60f618c679e8af95643b5d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43501601375 |
| NURL | `v0.91.1-112-gab45d9db` |
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
| _(floor: empty program)_ | _3.000_ | _2.930_ | _3.102_ | _23.462_ | _12.561_ |
| `lcg` | 36.190 | **36.099** | 36.242 | 1456.619 | 4136.672 |
| `packet_classifier` | 51.269 | **51.177** | 51.352 | 129.237 | 3402.765 |
| `ring_write` | 38.950 | **38.917** | 38.983 | 61.416 | 5011.473 |
| `histogram_bins` | 36.536 | **36.493** | 36.681 | 64.354 | 4419.935 |
| `prefix_scan` | 20.748 | **20.716** | 20.835 | 58.605 | 3304.686 |
| `binary_search` | 34.027 | 33.896 | **30.285** | 90.108 | 4759.943 |
| `sort_window` | 25.072 | **25.060** | 25.260 | 128.461 | 8578.859 |
| `bloom_filter` | **15.276** | 16.301 | 17.773 | 2110.714 | 6051.699 |
| `hash_join` | 22.657 | **22.523** | 25.173 | 2593.629 | 5762.256 |
| `sieve` | 20.801 | 23.767 | **20.634** | 62.462 | 2641.771 |
| `fib` | 27.644 | 27.688 | **23.692** | 118.152 | 894.403 |
| `collatz` | **12.401** | 12.422 | 12.555 | 45.194 | 555.901 |
| `matmul` | **37.050** | 37.480 | 38.105 | 62.591 | 2434.767 |
| `json_parse` | **6.477** | 10.884 | 15.041 | 33.284 | 28.092 |
| `nbody` | **21.978** | 41.129 | 22.717 | 76.612 | 2461.523 |
| `safe_record_array` | 55.572 | **48.610** | 56.658 | n/a | n/a |
| `payload_state_machine` | 66.625 | 64.781 | **64.601** | n/a | n/a |
| `captured_closure_queue` | 77.646 | **75.327** | 88.850 | n/a | n/a |
| `dynamic_method_mix` | 106.663 | **102.161** | 125.243 | n/a | n/a |
| `csv_table_pipeline` | **70.307** | 80.774 | 72.977 | n/a | n/a |
| `chacha20` | **6.306** | 34.306 | 29.508 | n/a | n/a |
| `poly1305` | **12.559** | 20.152 | 20.301 | n/a | n/a |
| `blake2b` | **38.907** | 57.051 | 62.702 | n/a | n/a |
| `sha512` | 40.737 | **40.441** | 44.270 | n/a | n/a |
| `x25519` | **30.559** | 44.457 | 45.433 | n/a | n/a |

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
| _(floor: empty program)_ | _6.410_ | _61.358_ | _**67.768**_ | _28.132_ | _35.113_ | _49.200_ |
| `lcg` | 6.315 | 66.398 | **72.713** | 28.426 | 41.576 | 53.983 |
| `packet_classifier` | 6.416 | 67.435 | **73.851** | 28.305 | 42.587 | 54.800 |
| `ring_write` | 12.202 | 68.996 | **81.198** | 33.943 | 43.120 | 55.736 |
| `histogram_bins` | 12.281 | 69.537 | **81.818** | 34.016 | 61.045 | 62.387 |
| `prefix_scan` | 12.406 | 69.732 | **82.138** | 34.332 | 45.939 | 58.948 |
| `binary_search` | 12.312 | 68.692 | **81.004** | 34.280 | 43.409 | 59.526 |
| `sort_window` | 12.354 | 70.745 | **83.099** | 34.063 | 49.299 | 63.733 |
| `bloom_filter` | 12.868 | 70.993 | **83.861** | 34.763 | 47.550 | 60.119 |
| `hash_join` | 15.739 | 120.562 | **136.301** | 37.514 | 96.341 | 95.977 |
| `sieve` | 12.193 | 69.207 | **81.400** | 34.059 | 49.776 | 65.022 |
| `fib` | 6.544 | 67.971 | **74.515** | 28.490 | 42.408 | 55.268 |
| `collatz` | 6.705 | 68.772 | **75.477** | 28.724 | 43.384 | 55.416 |
| `matmul` | 12.440 | 69.931 | **82.371** | 34.363 | 51.214 | 72.054 |
| `json_parse` | 40.100 | 172.867 | **212.967** | 63.548 | 76.882 | 134.585 |
| `nbody` | 14.104 | 74.710 | **88.814** | 35.910 | 62.758 | 84.667 |
| `safe_record_array` | 15.102 | 150.187 | **165.289** | 37.388 | 51.528 | 75.024 |
| `payload_state_machine` | 23.248 | 122.729 | **145.977** | 45.048 | 54.142 | 78.156 |
| `captured_closure_queue` | 18.075 | 176.999 | **195.074** | 40.517 | 61.267 | 98.384 |
| `dynamic_method_mix` | 17.803 | 174.130 | **191.933** | 40.042 | 57.977 | 91.859 |
| `csv_table_pipeline` | 69.263 | 372.091 | **441.354** | 91.469 | 148.369 | 209.339 |
| `chacha20` | 55.323 | 329.490 | **384.813** | 77.386 | 68.553 | 92.823 |
| `poly1305` | 44.979 | 200.974 | **245.953** | 66.859 | 70.697 | 104.590 |
| `blake2b` | 29.723 | 168.531 | **198.254** | 51.880 | 68.527 | 101.484 |
| `sha512` | 28.343 | 236.944 | **265.287** | 50.349 | 68.040 | 90.050 |
| `x25519` | 41.891 | 817.752 | **859.643** | 64.311 | 736.389 | 397.072 |

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
