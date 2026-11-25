# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-25T11:21:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `c46fd726f851b3938d5fbdea2c3dc3edabd20edf` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45602517536 |
| NURL | `v0.94.0-88-gc46fd726f` |
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
| _(floor: empty program)_ | _3.540_ | _3.575_ | _3.777_ | _27.765_ | _15.569_ |
| `lcg` | 41.256 | **41.248** | 41.407 | 1781.082 | 6249.295 |
| `packet_classifier` | **58.683** | 58.842 | 58.899 | 169.455 | 4064.322 |
| `ring_write` | **44.329** | 44.558 | 44.667 | 71.423 | 6204.193 |
| `histogram_bins` | 42.163 | 43.058 | **41.636** | 70.790 | 5691.319 |
| `prefix_scan` | **24.153** | 24.211 | 24.398 | 69.545 | 4068.202 |
| `binary_search` | 42.085 | 41.638 | **37.839** | 111.913 | 5952.621 |
| `sort_window` | 29.261 | **29.004** | 29.251 | 198.179 | 12004.696 |
| `bloom_filter` | **18.305** | 20.172 | 20.946 | 2800.082 | 7026.797 |
| `hash_join` | **29.039** | 29.266 | 32.005 | 3379.393 | 7662.201 |
| `sieve` | 27.440 | 30.105 | **27.017** | 74.371 | 3211.780 |
| `fib` | 32.227 | 32.090 | **27.712** | 136.077 | 1100.504 |
| `collatz` | 14.808 | **14.676** | 14.752 | 55.250 | 678.748 |
| `matmul` | 36.283 | **36.203** | 36.430 | 73.852 | 3071.832 |
| `json_parse` | **8.193** | 13.631 | 18.724 | 40.691 | 38.566 |
| `nbody` | **26.604** | 48.982 | 27.616 | 104.797 | 2980.144 |
| `safe_record_array` | 58.958 | **57.590** | 65.908 | n/a | n/a |
| `payload_state_machine` | 77.813 | **73.280** | 75.837 | n/a | n/a |
| `captured_closure_queue` | 93.228 | **87.531** | 104.128 | n/a | n/a |
| `dynamic_method_mix` | 143.635 | **117.976** | 149.402 | n/a | n/a |
| `csv_table_pipeline` | **85.337** | 98.539 | 88.468 | n/a | n/a |
| `chacha20` | **9.858** | 41.208 | 33.669 | n/a | n/a |
| `poly1305` | **13.930** | 23.388 | 23.677 | n/a | n/a |
| `blake2b` | **44.548** | 67.097 | 72.003 | n/a | n/a |
| `sha512` | **49.276** | 49.419 | 51.891 | n/a | n/a |
| `x25519` | **36.003** | 51.126 | 52.600 | n/a | n/a |

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
| _(floor: empty program)_ | _6.405_ | _75.753_ | _**82.158**_ | _31.246_ | _41.706_ | _75.304_ |
| `lcg` | 6.564 | 81.576 | **88.140** | 31.761 | 48.820 | 74.043 |
| `packet_classifier` | 6.991 | 82.401 | **89.392** | 32.396 | 49.518 | 72.913 |
| `ring_write` | 13.581 | 82.415 | **95.996** | 38.790 | 50.491 | 75.271 |
| `histogram_bins` | 14.228 | 85.229 | **99.457** | 40.060 | 74.076 | 85.661 |
| `prefix_scan` | 14.262 | 85.423 | **99.685** | 39.630 | 55.076 | 80.958 |
| `binary_search` | 14.265 | 86.257 | **100.522** | 40.781 | 53.471 | 82.930 |
| `sort_window` | 14.025 | 84.630 | **98.655** | 39.111 | 58.605 | 90.176 |
| `bloom_filter` | 14.808 | 85.232 | **100.040** | 39.813 | 54.982 | 84.080 |
| `hash_join` | 18.556 | 145.816 | **164.372** | 43.014 | 118.939 | 126.196 |
| `sieve` | 14.454 | 85.262 | **99.716** | 40.477 | 60.042 | 90.351 |
| `fib` | 6.779 | 81.699 | **88.478** | 31.921 | 48.979 | 77.167 |
| `collatz` | 6.919 | 82.488 | **89.407** | 31.747 | 50.335 | 76.504 |
| `matmul` | 14.907 | 85.664 | **100.571** | 40.618 | 59.660 | 107.222 |
| `json_parse` | 49.542 | 228.781 | **278.323** | 75.504 | 93.737 | 182.035 |
| `nbody` | 15.843 | 89.169 | **105.012** | 41.083 | 74.219 | 113.097 |
| `safe_record_array` | 17.673 | 187.863 | **205.536** | 43.186 | 61.211 | 104.082 |
| `payload_state_machine` | 27.818 | 154.703 | **182.521** | 53.560 | 63.738 | 107.174 |
| `captured_closure_queue` | 21.871 | 220.721 | **242.592** | 47.238 | 72.301 | 135.244 |
| `dynamic_method_mix` | 21.492 | 221.443 | **242.935** | 47.138 | 69.908 | 124.897 |
| `csv_table_pipeline` | 87.916 | 507.853 | **595.769** | 113.918 | 187.636 | 281.631 |
| `chacha20` | 72.444 | 455.307 | **527.751** | 98.211 | 81.519 | 127.123 |
| `poly1305` | 58.827 | 257.254 | **316.081** | 85.228 | 86.174 | 141.923 |
| `blake2b` | 37.355 | 214.878 | **252.233** | 63.521 | 82.916 | 138.408 |
| `sha512` | 35.551 | 308.534 | **344.085** | 62.091 | 82.460 | 122.171 |
| `x25519` | 53.929 | 1073.914 | **1127.843** | 80.176 | 968.253 | 521.780 |

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
