# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-21T14:31:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ccd62aa2d5748851779da97b44ffd203c821ea5b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44913791270 |
| NURL | `v0.93.0` |
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
| _(floor: empty program)_ | _3.451_ | _3.318_ | _3.546_ | _27.945_ | _14.935_ |
| `lcg` | **41.588** | 41.652 | 41.740 | 1784.597 | 5228.797 |
| `packet_classifier` | **58.371** | 58.417 | 58.711 | 168.629 | 4192.668 |
| `ring_write` | 44.356 | **44.300** | 44.622 | 70.881 | 6069.069 |
| `histogram_bins` | 41.547 | 42.861 | **41.402** | 72.134 | 5619.818 |
| `prefix_scan` | 23.820 | **23.556** | 23.764 | 68.798 | 4150.261 |
| `binary_search` | 41.760 | 41.516 | **37.558** | 110.212 | 5862.186 |
| `sort_window` | **29.207** | 29.253 | 29.288 | 198.568 | 12039.820 |
| `bloom_filter` | **17.669** | 19.692 | 20.685 | 2783.765 | 7489.467 |
| `hash_join` | 28.905 | **28.595** | 31.900 | 3334.190 | 7656.100 |
| `sieve` | 24.758 | 28.221 | **24.727** | 72.858 | 3136.970 |
| `fib` | 32.478 | 32.207 | **27.928** | 139.970 | 1092.472 |
| `collatz` | 14.331 | **14.233** | 14.377 | 54.919 | 694.490 |
| `matmul` | 36.302 | **36.152** | 36.327 | 78.018 | 2857.064 |
| `json_parse` | **8.241** | 13.278 | 18.234 | 40.892 | 37.708 |
| `nbody` | **26.886** | 49.160 | 27.880 | 105.149 | 2981.836 |
| `safe_record_array` | 58.916 | **57.532** | 65.895 | n/a | n/a |
| `payload_state_machine` | 77.261 | **73.256** | 75.795 | n/a | n/a |
| `captured_closure_queue` | 90.810 | **87.557** | 104.520 | n/a | n/a |
| `dynamic_method_mix` | 121.917 | **117.725** | 149.622 | n/a | n/a |
| `csv_table_pipeline` | **85.276** | 97.647 | 88.229 | n/a | n/a |
| `chacha20` | **10.124** | 41.357 | 33.693 | n/a | n/a |
| `poly1305` | **13.907** | 23.375 | 23.723 | n/a | n/a |
| `blake2b` | **43.793** | 66.835 | 71.590 | n/a | n/a |
| `sha512` | **48.978** | 49.255 | 51.783 | n/a | n/a |
| `x25519` | **35.825** | 51.162 | 52.374 | n/a | n/a |

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
| _(floor: empty program)_ | _7.260_ | _74.482_ | _**81.742**_ | _33.605_ | _41.266_ | _64.832_ |
| `lcg` | 7.058 | 77.665 | **84.723** | 31.150 | 47.573 | 72.398 |
| `packet_classifier` | 7.392 | 83.466 | **90.858** | 32.991 | 50.538 | 74.010 |
| `ring_write` | 14.624 | 82.976 | **97.600** | 39.706 | 49.782 | 76.898 |
| `histogram_bins` | 14.693 | 83.924 | **98.617** | 40.145 | 72.835 | 82.921 |
| `prefix_scan` | 15.565 | 86.364 | **101.929** | 40.839 | 53.982 | 78.621 |
| `binary_search` | 14.628 | 81.528 | **96.156** | 39.434 | 49.759 | 80.366 |
| `sort_window` | 15.011 | 84.423 | **99.434** | 40.165 | 58.680 | 99.536 |
| `bloom_filter` | 15.909 | 85.952 | **101.861** | 41.487 | 56.338 | 82.192 |
| `hash_join` | 19.258 | 148.247 | **167.505** | 44.078 | 119.191 | 125.173 |
| `sieve` | 14.693 | 83.210 | **97.903** | 39.612 | 58.099 | 86.640 |
| `fib` | 7.431 | 79.400 | **86.831** | 31.918 | 48.041 | 72.980 |
| `collatz` | 7.548 | 80.314 | **87.862** | 31.992 | 49.204 | 73.190 |
| `matmul` | 14.928 | 82.690 | **97.618** | 39.733 | 59.961 | 101.579 |
| `json_parse` | 50.985 | 216.689 | **267.674** | 76.809 | 92.885 | 180.251 |
| `nbody` | 16.978 | 97.619 | **114.597** | 44.001 | 78.791 | 128.436 |
| `safe_record_array` | 18.816 | 187.843 | **206.659** | 43.948 | 60.528 | 101.989 |
| `payload_state_machine` | 28.557 | 153.306 | **181.863** | 54.142 | 64.809 | 106.592 |
| `captured_closure_queue` | 23.427 | 224.250 | **247.677** | 49.681 | 73.975 | 144.872 |
| `dynamic_method_mix` | 22.785 | 221.253 | **244.038** | 49.558 | 69.630 | 128.295 |
| `csv_table_pipeline` | 90.537 | 488.984 | **579.521** | 116.799 | 186.337 | 275.538 |
| `chacha20` | 72.241 | 422.902 | **495.143** | 98.302 | 82.652 | 131.525 |
| `poly1305` | 60.148 | 255.065 | **315.213** | 85.958 | 86.553 | 140.384 |
| `blake2b` | 38.305 | 215.175 | **253.480** | 64.410 | 81.774 | 141.070 |
| `sha512` | 37.290 | 302.202 | **339.492** | 62.896 | 81.247 | 124.864 |
| `x25519` | 55.246 | 1074.374 | **1129.620** | 81.109 | 968.116 | 522.724 |

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
