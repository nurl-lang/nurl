# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-15T09:27:02Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `3358873a0db175ddc87715bf0fda48342fa5514c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43698743876 |
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
| _(floor: empty program)_ | _3.433_ | _3.405_ | _3.650_ | _28.761_ | _15.227_ |
| `lcg` | 41.237 | **41.104** | 41.295 | 1921.954 | 4847.569 |
| `packet_classifier` | 58.595 | **58.306** | 58.579 | 166.774 | 4056.121 |
| `ring_write` | 44.518 | **44.352** | 44.564 | 72.276 | 6077.753 |
| `histogram_bins` | 41.676 | 42.606 | **41.244** | 72.063 | 5854.019 |
| `prefix_scan` | 23.775 | **23.607** | 23.781 | 68.786 | 4090.093 |
| `binary_search` | 41.578 | 41.588 | **37.597** | 110.211 | 6084.049 |
| `sort_window` | **28.785** | 28.864 | 28.796 | 199.700 | 12688.609 |
| `bloom_filter` | **17.530** | 19.477 | 20.456 | 2872.271 | 7126.721 |
| `hash_join` | **28.941** | 29.179 | 31.832 | 3492.570 | 7667.767 |
| `sieve` | **26.220** | 29.534 | 26.404 | 73.976 | 3283.394 |
| `fib` | 32.222 | 32.149 | **27.237** | 135.919 | 1127.375 |
| `collatz` | 14.271 | **14.152** | 14.403 | 53.864 | 695.057 |
| `matmul` | 35.564 | **35.541** | 35.859 | 76.097 | 3112.753 |
| `json_parse` | **8.478** | 13.404 | 18.486 | 40.948 | 38.648 |
| `nbody` | **26.481** | 48.767 | 27.485 | 103.959 | 2988.139 |
| `safe_record_array` | 63.761 | **57.158** | 65.432 | n/a | n/a |
| `payload_state_machine` | 76.981 | **72.944** | 75.390 | n/a | n/a |
| `captured_closure_queue` | 90.477 | **87.239** | 103.800 | n/a | n/a |
| `dynamic_method_mix` | 121.876 | **117.207** | 149.508 | n/a | n/a |
| `csv_table_pipeline` | **83.919** | 94.295 | 86.147 | n/a | n/a |
| `chacha20` | **9.517** | 40.989 | 33.193 | n/a | n/a |
| `poly1305` | **13.649** | 22.895 | 23.175 | n/a | n/a |
| `blake2b` | **43.334** | 66.423 | 71.431 | n/a | n/a |
| `sha512` | **48.209** | 49.025 | 51.471 | n/a | n/a |
| `x25519` | **35.432** | 50.982 | 52.379 | n/a | n/a |

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
| _(floor: empty program)_ | _7.124_ | _70.584_ | _**77.708**_ | _31.593_ | _39.801_ | _55.870_ |
| `lcg` | 7.134 | 79.311 | **86.445** | 31.645 | 47.197 | 61.631 |
| `packet_classifier` | 7.312 | 79.605 | **86.917** | 31.871 | 48.130 | 62.199 |
| `ring_write` | 14.279 | 81.675 | **95.954** | 38.631 | 48.828 | 64.067 |
| `histogram_bins` | 14.477 | 82.625 | **97.102** | 38.721 | 71.188 | 70.817 |
| `prefix_scan` | 14.462 | 80.838 | **95.300** | 38.675 | 52.184 | 67.115 |
| `binary_search` | 14.714 | 80.547 | **95.261** | 38.946 | 49.626 | 68.017 |
| `sort_window` | 14.777 | 84.762 | **99.539** | 39.025 | 56.103 | 73.189 |
| `bloom_filter` | 15.471 | 82.037 | **97.508** | 39.522 | 53.927 | 69.356 |
| `hash_join` | 19.382 | 146.856 | **166.238** | 43.680 | 116.949 | 114.597 |
| `sieve` | 14.862 | 82.224 | **97.086** | 39.673 | 57.680 | 75.552 |
| `fib` | 7.342 | 79.008 | **86.350** | 31.883 | 47.551 | 62.339 |
| `collatz` | 7.490 | 80.254 | **87.744** | 31.851 | 48.717 | 62.883 |
| `matmul` | 15.113 | 81.732 | **96.845** | 39.847 | 60.524 | 87.010 |
| `json_parse` | 48.978 | 208.863 | **257.841** | 73.877 | 90.075 | 164.815 |
| `nbody` | 16.519 | 86.703 | **103.222** | 41.081 | 72.468 | 98.311 |
| `safe_record_array` | 18.182 | 181.939 | **200.121** | 42.716 | 58.377 | 87.659 |
| `payload_state_machine` | 28.075 | 148.388 | **176.463** | 52.415 | 62.277 | 90.894 |
| `captured_closure_queue` | 22.273 | 216.258 | **238.531** | 47.093 | 70.490 | 116.801 |
| `dynamic_method_mix` | 21.879 | 210.122 | **232.001** | 46.507 | 66.895 | 108.440 |
| `csv_table_pipeline` | 87.228 | 470.262 | **557.490** | 112.117 | 181.579 | 255.358 |
| `chacha20` | 71.734 | 409.789 | **481.523** | 97.096 | 79.370 | 110.686 |
| `poly1305` | 59.185 | 248.630 | **307.815** | 83.574 | 83.352 | 124.342 |
| `blake2b` | 36.856 | 205.573 | **242.429** | 61.528 | 79.335 | 119.883 |
| `sha512` | 36.007 | 293.802 | **329.809** | 60.341 | 78.915 | 105.836 |
| `x25519` | 53.384 | 1047.460 | **1100.844** | 78.467 | 954.414 | 498.783 |

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
