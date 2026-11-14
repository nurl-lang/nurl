# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-14T12:11:57Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `8072dbd76286c2c27a6460f895fa11b22fa80c95` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43593125744 |
| NURL | `v0.92.0` |
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
| _(floor: empty program)_ | _3.004_ | _3.028_ | _3.239_ | _24.067_ | _12.945_ |
| `lcg` | 36.353 | **36.000** | 36.292 | 1459.632 | 4105.239 |
| `packet_classifier` | 51.292 | **51.282** | 51.396 | 127.869 | 3351.388 |
| `ring_write` | 38.913 | **38.774** | 39.062 | 63.168 | 4884.342 |
| `histogram_bins` | **36.740** | 36.795 | 37.038 | 64.031 | 4572.567 |
| `prefix_scan` | 20.882 | **20.786** | 20.972 | 58.789 | 3248.164 |
| `binary_search` | 34.261 | 34.027 | **30.482** | 90.768 | 4841.674 |
| `sort_window` | 25.156 | **25.109** | 25.221 | 129.596 | 8293.624 |
| `bloom_filter` | **15.349** | 16.418 | 17.961 | 2132.461 | 5614.588 |
| `hash_join` | 22.723 | **22.580** | 25.190 | 2639.689 | 5675.383 |
| `sieve` | **20.629** | 23.767 | 20.655 | 62.127 | 2510.229 |
| `fib` | 27.869 | 27.779 | **23.808** | 117.253 | 889.333 |
| `collatz` | **12.360** | 12.426 | 12.597 | 45.564 | 562.825 |
| `matmul` | **37.509** | 38.366 | 37.979 | 63.898 | 2405.220 |
| `json_parse` | **6.456** | 10.881 | 15.209 | 34.064 | 29.063 |
| `nbody` | **22.298** | 41.431 | 22.982 | 78.368 | 2442.288 |
| `safe_record_array` | 55.400 | **48.689** | 56.558 | n/a | n/a |
| `payload_state_machine` | 66.481 | 64.575 | **64.528** | n/a | n/a |
| `captured_closure_queue` | 77.333 | **75.223** | 88.687 | n/a | n/a |
| `dynamic_method_mix` | 105.688 | **101.820** | 125.351 | n/a | n/a |
| `csv_table_pipeline` | **70.817** | 81.408 | 73.078 | n/a | n/a |
| `chacha20` | **6.268** | 34.235 | 29.651 | n/a | n/a |
| `poly1305` | **12.654** | 20.101 | 20.372 | n/a | n/a |
| `blake2b` | **39.028** | 57.063 | 62.880 | n/a | n/a |
| `sha512` | 40.794 | **40.517** | 44.527 | n/a | n/a |
| `x25519` | **30.927** | 44.498 | 45.848 | n/a | n/a |

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
| _(floor: empty program)_ | _6.198_ | _63.921_ | _**70.119**_ | _28.396_ | _37.249_ | _52.655_ |
| `lcg` | 6.512 | 68.543 | **75.055** | 28.807 | 42.168 | 53.454 |
| `packet_classifier` | 6.309 | 66.565 | **72.874** | 27.843 | 42.644 | 54.813 |
| `ring_write` | 12.349 | 70.197 | **82.546** | 34.307 | 43.804 | 56.430 |
| `histogram_bins` | 12.506 | 71.204 | **83.710** | 34.542 | 62.707 | 63.069 |
| `prefix_scan` | 12.645 | 71.454 | **84.099** | 34.621 | 46.965 | 59.431 |
| `binary_search` | 12.399 | 69.312 | **81.711** | 34.263 | 44.206 | 59.562 |
| `sort_window` | 12.453 | 70.341 | **82.794** | 34.788 | 49.256 | 63.989 |
| `bloom_filter` | 13.127 | 72.934 | **86.061** | 35.676 | 49.680 | 61.866 |
| `hash_join` | 15.904 | 120.540 | **136.444** | 37.787 | 97.103 | 97.100 |
| `sieve` | 12.601 | 70.801 | **83.402** | 34.358 | 50.092 | 64.464 |
| `fib` | 6.754 | 68.668 | **75.422** | 28.917 | 44.348 | 55.013 |
| `collatz` | 6.645 | 69.358 | **76.003** | 29.331 | 44.201 | 54.668 |
| `matmul` | 12.896 | 71.845 | **84.741** | 35.103 | 51.851 | 72.538 |
| `json_parse` | 39.796 | 174.198 | **213.994** | 62.340 | 77.674 | 134.992 |
| `nbody` | 13.967 | 74.053 | **88.020** | 35.839 | 63.756 | 82.980 |
| `safe_record_array` | 15.047 | 149.511 | **164.558** | 37.224 | 50.989 | 74.670 |
| `payload_state_machine` | 23.059 | 123.534 | **146.593** | 44.621 | 54.335 | 77.460 |
| `captured_closure_queue` | 18.325 | 175.514 | **193.839** | 40.312 | 60.643 | 98.565 |
| `dynamic_method_mix` | 17.618 | 172.459 | **190.077** | 39.628 | 58.102 | 91.832 |
| `csv_table_pipeline` | 70.066 | 378.133 | **448.199** | 92.389 | 148.510 | 208.649 |
| `chacha20` | 56.191 | 329.930 | **386.121** | 77.808 | 68.500 | 93.048 |
| `poly1305` | 45.083 | 201.935 | **247.018** | 66.996 | 71.175 | 104.366 |
| `blake2b` | 29.886 | 169.714 | **199.600** | 51.998 | 68.296 | 101.672 |
| `sha512` | 29.176 | 235.877 | **265.053** | 50.905 | 68.640 | 89.575 |
| `x25519` | 42.334 | 819.698 | **862.032** | 64.614 | 735.536 | 401.346 |

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
