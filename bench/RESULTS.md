# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-16T09:44:08Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16365628 KiB |
| Commit | `3358873a0db175ddc87715bf0fda48342fa5514c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43841301819 |
| NURL | `v0.92.1-1-g3358873a` |
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
| _(floor: empty program)_ | _2.864_ | _2.936_ | _2.957_ | _30.106_ | _15.216_ |
| `lcg` | 39.977 | 39.949 | **39.797** | 1786.446 | 5154.811 |
| `packet_classifier` | 55.368 | **55.364** | 55.714 | 165.546 | 4152.876 |
| `ring_write` | 42.926 | **42.868** | 43.721 | 77.268 | 6492.692 |
| `histogram_bins` | 42.825 | 43.352 | **40.420** | 77.271 | 6018.133 |
| `prefix_scan` | 23.023 | 22.807 | **22.795** | 73.906 | 4120.205 |
| `binary_search` | 37.529 | 37.298 | **31.750** | 112.169 | 6036.619 |
| `sort_window` | 38.390 | **37.241** | 38.346 | 188.371 | 10983.296 |
| `bloom_filter` | **16.049** | 17.508 | 16.772 | 2822.582 | 7292.077 |
| `hash_join` | 26.413 | **25.768** | 29.101 | 3464.034 | 7314.768 |
| `sieve` | 39.428 | 40.575 | **38.979** | 95.785 | 3615.197 |
| `fib` | 29.035 | 28.771 | **27.959** | 132.932 | 984.590 |
| `collatz` | 15.092 | 15.057 | **14.809** | 64.748 | 641.273 |
| `matmul` | 19.660 | 19.851 | **19.623** | 78.592 | 2842.214 |
| `json_parse` | **7.458** | 11.308 | 14.921 | 41.847 | 36.797 |
| `nbody` | **24.173** | 38.258 | 24.197 | 96.982 | 2501.292 |
| `safe_record_array` | 67.575 | **58.396** | 61.662 | n/a | n/a |
| `payload_state_machine` | 82.129 | **78.635** | 79.126 | n/a | n/a |
| `captured_closure_queue` | 91.526 | **83.352** | 101.740 | n/a | n/a |
| `dynamic_method_mix` | 114.257 | **108.296** | 110.353 | n/a | n/a |
| `csv_table_pipeline` | **90.295** | 102.277 | 94.007 | n/a | n/a |
| `chacha20` | **6.631** | 36.134 | 35.760 | n/a | n/a |
| `poly1305` | **11.773** | 27.670 | 27.976 | n/a | n/a |
| `blake2b` | **45.983** | 57.390 | 68.879 | n/a | n/a |
| `sha512` | 47.767 | **46.849** | 51.825 | n/a | n/a |
| `x25519` | **33.053** | 52.640 | 52.446 | n/a | n/a |

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
| _(floor: empty program)_ | _6.965_ | _69.472_ | _**76.437**_ | _29.525_ | _36.817_ | _56.376_ |
| `lcg` | 7.194 | 79.244 | **86.438** | 30.113 | 42.379 | 62.690 |
| `packet_classifier` | 7.402 | 78.952 | **86.354** | 30.467 | 44.802 | 64.103 |
| `ring_write` | 14.562 | 78.389 | **92.951** | 36.887 | 45.115 | 65.517 |
| `histogram_bins` | 14.375 | 78.254 | **92.629** | 36.475 | 66.861 | 74.349 |
| `prefix_scan` | 14.458 | 77.241 | **91.699** | 36.869 | 48.415 | 68.944 |
| `binary_search` | 14.253 | 78.218 | **92.471** | 36.397 | 45.197 | 69.503 |
| `sort_window` | 14.504 | 79.247 | **93.751** | 37.145 | 51.801 | 76.420 |
| `bloom_filter` | 15.156 | 83.931 | **99.087** | 37.747 | 51.076 | 74.017 |
| `hash_join` | 19.141 | 143.237 | **162.378** | 42.231 | 111.018 | 117.477 |
| `sieve` | 14.363 | 77.612 | **91.975** | 36.803 | 54.625 | 75.830 |
| `fib` | 7.419 | 75.899 | **83.318** | 29.719 | 44.073 | 64.767 |
| `collatz` | 7.556 | 77.925 | **85.481** | 29.743 | 45.628 | 64.339 |
| `matmul` | 15.133 | 79.643 | **94.776** | 38.030 | 55.963 | 84.611 |
| `json_parse` | 48.374 | 215.284 | **263.658** | 71.493 | 86.514 | 170.935 |
| `nbody` | 16.119 | 83.571 | **99.690** | 38.306 | 67.979 | 101.287 |
| `safe_record_array` | 17.972 | 187.114 | **205.086** | 41.169 | 55.927 | 92.852 |
| `payload_state_machine` | 27.774 | 149.950 | **177.724** | 51.282 | 58.748 | 94.520 |
| `captured_closure_queue` | 22.528 | 221.715 | **244.243** | 45.519 | 67.207 | 121.571 |
| `dynamic_method_mix` | 21.503 | 217.917 | **239.420** | 45.128 | 63.134 | 112.924 |
| `csv_table_pipeline` | 85.838 | 489.171 | **575.009** | 109.557 | 180.989 | 269.424 |
| `chacha20` | 69.139 | 425.194 | **494.333** | 92.070 | 76.052 | 116.465 |
| `poly1305` | 55.822 | 248.372 | **304.194** | 78.760 | 80.944 | 130.028 |
| `blake2b` | 36.322 | 208.430 | **244.752** | 58.965 | 77.380 | 125.109 |
| `sha512` | 35.102 | 295.345 | **330.447** | 57.906 | 76.147 | 111.573 |
| `x25519` | 51.972 | 1056.016 | **1107.988** | 74.496 | 929.527 | 505.869 |

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
