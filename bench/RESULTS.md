# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-23T10:49:34Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `3ac7f6e2e03db20ce6311b6b020d827fefb8902e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45158614919 |
| NURL | `v0.94.0-42-g3ac7f6e2` |
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
| _(floor: empty program)_ | _3.254_ | _3.027_ | _3.307_ | _26.254_ | _14.143_ |
| `lcg` | 36.695 | **36.586** | 36.841 | 1482.118 | 4079.905 |
| `packet_classifier` | 51.510 | **51.452** | 51.681 | 129.255 | 3336.564 |
| `ring_write` | **39.375** | 39.406 | 39.553 | 63.994 | 4874.831 |
| `histogram_bins` | **36.903** | 36.985 | 37.134 | 65.250 | 4585.740 |
| `prefix_scan` | **21.465** | **21.465** | 21.757 | 62.312 | 3242.200 |
| `binary_search` | 34.571 | 34.595 | **31.272** | 91.895 | 4926.067 |
| `sort_window` | **25.645** | 25.650 | 25.826 | 130.225 | 9587.766 |
| `bloom_filter` | **16.074** | 17.153 | 18.653 | 2187.394 | 5809.349 |
| `hash_join` | **23.317** | 23.329 | 25.850 | 2652.063 | 5699.105 |
| `sieve` | 21.359 | 24.393 | **21.024** | 65.047 | 2480.100 |
| `fib` | 28.165 | 28.189 | **24.174** | 119.697 | 902.678 |
| `collatz` | 13.041 | **12.983** | 13.086 | 48.403 | 549.115 |
| `matmul` | **37.705** | 38.462 | 38.540 | 66.864 | 2479.745 |
| `json_parse` | **7.098** | 11.581 | 15.634 | 38.252 | 31.037 |
| `nbody` | **22.576** | 41.679 | 23.379 | 80.153 | 2474.833 |
| `safe_record_array` | 50.614 | **49.113** | 57.106 | n/a | n/a |
| `payload_state_machine` | 66.802 | 64.970 | **64.800** | n/a | n/a |
| `captured_closure_queue` | 77.411 | **75.503** | 88.830 | n/a | n/a |
| `dynamic_method_mix` | 106.834 | **102.179** | 125.847 | n/a | n/a |
| `csv_table_pipeline` | **73.010** | 86.706 | 76.173 | n/a | n/a |
| `chacha20` | **6.784** | 34.953 | 30.254 | n/a | n/a |
| `poly1305` | **13.400** | 21.081 | 21.144 | n/a | n/a |
| `blake2b` | **39.304** | 57.402 | 62.974 | n/a | n/a |
| `sha512` | 41.182 | **40.833** | 44.642 | n/a | n/a |
| `x25519` | **31.129** | 44.861 | 45.807 | n/a | n/a |

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
| _(floor: empty program)_ | _6.915_ | _67.373_ | _**74.288**_ | _30.408_ | _39.668_ | _60.304_ |
| `lcg` | 7.153 | 75.038 | **82.191** | 31.108 | 44.666 | 67.469 |
| `packet_classifier` | 6.886 | 72.441 | **79.327** | 30.156 | 45.710 | 66.767 |
| `ring_write` | 13.135 | 74.812 | **87.947** | 36.943 | 47.603 | 70.335 |
| `histogram_bins` | 13.132 | 74.668 | **87.800** | 36.856 | 65.625 | 78.346 |
| `prefix_scan` | 13.125 | 74.944 | **88.069** | 36.759 | 50.037 | 73.587 |
| `binary_search` | 13.380 | 75.549 | **88.929** | 37.268 | 48.124 | 74.525 |
| `sort_window` | 13.491 | 76.498 | **89.989** | 37.235 | 53.193 | 79.243 |
| `bloom_filter` | 13.896 | 76.015 | **89.911** | 37.799 | 51.405 | 75.803 |
| `hash_join` | 17.115 | 129.343 | **146.458** | 41.355 | 103.177 | 115.488 |
| `sieve` | 13.466 | 77.153 | **90.619** | 37.256 | 53.803 | 80.897 |
| `fib` | 7.251 | 75.983 | **83.234** | 31.320 | 47.290 | 69.797 |
| `collatz` | 7.491 | 76.591 | **84.082** | 31.790 | 46.603 | 70.244 |
| `matmul` | 13.817 | 77.886 | **91.703** | 38.221 | 56.183 | 88.654 |
| `json_parse` | 42.373 | 181.956 | **224.329** | 67.305 | 82.823 | 157.348 |
| `nbody` | 15.100 | 78.476 | **93.576** | 39.149 | 66.510 | 101.762 |
| `safe_record_array` | 16.853 | 162.852 | **179.705** | 41.122 | 56.215 | 93.465 |
| `payload_state_machine` | 24.200 | 130.124 | **154.324** | 47.928 | 58.951 | 97.653 |
| `captured_closure_queue` | 20.120 | 187.113 | **207.233** | 44.115 | 64.974 | 118.475 |
| `dynamic_method_mix` | 19.639 | 186.058 | **205.697** | 43.726 | 62.943 | 113.669 |
| `csv_table_pipeline` | 73.648 | 398.053 | **471.701** | 98.123 | 155.195 | 230.177 |
| `chacha20` | 59.760 | 351.750 | **411.510** | 84.743 | 73.508 | 112.990 |
| `poly1305` | 48.575 | 213.060 | **261.635** | 73.320 | 76.336 | 125.972 |
| `blake2b` | 32.567 | 183.060 | **215.627** | 57.449 | 73.960 | 120.964 |
| `sha512` | 30.271 | 247.516 | **277.787** | 54.585 | 74.010 | 112.607 |
| `x25519` | 45.614 | 848.269 | **893.883** | 69.484 | 759.628 | 424.709 |

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
