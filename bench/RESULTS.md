# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-11T13:08:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `b06ddf6fe9ec098eab4e0a54822a2cb91b6dbd3d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43025635736 |
| NURL | `v0.91.0` |
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
| _(floor: empty program)_ | _2.972_ | _2.873_ | _3.048_ | _22.404_ | _12.328_ |
| `lcg` | 36.105 | **35.981** | 36.144 | 1454.156 | 3973.140 |
| `packet_classifier` | 51.264 | **51.152** | 51.297 | 127.477 | 3400.850 |
| `ring_write` | 38.889 | **38.751** | 38.967 | 60.015 | 4818.842 |
| `histogram_bins` | 36.525 | **36.430** | 36.610 | 63.079 | 4652.627 |
| `prefix_scan` | 20.753 | **20.650** | 20.907 | 56.474 | 3242.302 |
| `binary_search` | **33.960** | 33.986 | 35.478 | 89.108 | 6265.944 |
| `sort_window` | 25.143 | **25.029** | 25.174 | 126.390 | 8492.605 |
| `bloom_filter` | **15.246** | 16.265 | 17.778 | 2121.100 | 5688.726 |
| `hash_join` | 22.681 | **22.590** | 25.206 | 2590.290 | 5991.746 |
| `sieve` | 21.611 | 23.468 | **19.825** | 61.174 | 2459.334 |
| `fib` | 27.633 | **27.511** | 27.653 | 116.175 | 885.020 |
| `collatz` | 12.387 | **12.332** | 12.574 | 43.529 | 576.548 |
| `matmul` | **36.839** | 37.542 | 37.265 | 61.687 | 2513.590 |
| `json_parse` | **6.464** | 10.725 | 15.059 | 32.228 | 27.937 |
| `nbody` | **21.963** | 41.060 | 22.625 | 81.806 | 2483.250 |
| `safe_record_array` | 54.699 | **48.716** | 56.571 | n/a | n/a |
| `payload_state_machine` | 75.658 | **64.623** | 65.800 | n/a | n/a |
| `captured_closure_queue` | 77.299 | **75.237** | 88.121 | n/a | n/a |
| `dynamic_method_mix` | 104.991 | **101.832** | 125.164 | n/a | n/a |
| `csv_table_pipeline` | **69.769** | 79.191 | 72.057 | n/a | n/a |
| `chacha20` | **6.273** | 34.124 | 29.310 | n/a | n/a |
| `poly1305` | **12.547** | 20.041 | 20.225 | n/a | n/a |
| `blake2b` | **40.174** | 56.968 | 62.592 | n/a | n/a |
| `sha512` | 40.505 | **40.220** | 44.095 | n/a | n/a |
| `x25519` | **30.254** | 44.330 | 45.136 | n/a | n/a |

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
| _(floor: empty program)_ | _5.976_ | _60.634_ | _**66.610**_ | _27.933_ | _34.910_ | _55.455_ |
| `lcg` | 6.074 | 64.758 | **70.832** | 27.362 | 40.571 | 62.001 |
| `packet_classifier` | 6.211 | 66.090 | **72.301** | 27.631 | 41.659 | 62.602 |
| `ring_write` | 13.297 | 67.199 | **80.496** | 34.560 | 42.160 | 63.985 |
| `histogram_bins` | 13.377 | 68.220 | **81.597** | 34.594 | 59.767 | 68.840 |
| `prefix_scan` | 13.340 | 67.555 | **80.895** | 34.473 | 44.923 | 65.939 |
| `binary_search` | 13.410 | 67.408 | **80.818** | 34.940 | 42.991 | 67.738 |
| `sort_window` | 13.544 | 69.823 | **83.367** | 34.818 | 48.536 | 71.638 |
| `bloom_filter` | 13.875 | 69.555 | **83.430** | 35.174 | 46.630 | 67.998 |
| `hash_join` | 16.445 | 117.162 | **133.607** | 37.859 | 94.945 | 103.824 |
| `sieve` | 13.316 | 67.814 | **81.130** | 34.951 | 48.673 | 73.369 |
| `fib` | 6.470 | 65.661 | **72.131** | 27.768 | 41.313 | 62.361 |
| `collatz` | 6.234 | 66.937 | **73.171** | 27.794 | 41.984 | 62.915 |
| `matmul` | 13.687 | 67.615 | **81.302** | 34.871 | 49.920 | 80.501 |
| `json_parse` | 38.575 | 162.895 | **201.470** | 60.229 | 75.308 | 145.025 |
| `nbody` | 14.769 | 71.358 | **86.127** | 36.093 | 60.915 | 92.841 |
| `safe_record_array` | 15.862 | 114.449 | **130.311** | 37.588 | 50.333 | 84.910 |
| `payload_state_machine` | 23.971 | 96.817 | **120.788** | 45.392 | 52.915 | 88.628 |
| `captured_closure_queue` | 18.613 | 149.732 | **168.345** | 40.341 | 59.372 | 108.715 |
| `dynamic_method_mix` | 17.927 | 146.692 | **164.619** | 39.652 | 56.886 | 101.958 |
| `csv_table_pipeline` | 69.804 | 375.045 | **444.849** | 91.726 | 147.729 | 219.198 |
| `chacha20` | 53.964 | 342.247 | **396.211** | 75.449 | 67.275 | 102.235 |
| `poly1305` | 44.834 | 201.743 | **246.577** | 66.302 | 70.112 | 113.936 |
| `blake2b` | 30.061 | 170.816 | **200.877** | 51.778 | 67.286 | 110.137 |
| `sha512` | 28.842 | 236.979 | **265.821** | 50.375 | 66.499 | 98.894 |
| `x25519` | 41.146 | 816.086 | **857.232** | 62.901 | 734.613 | 405.681 |

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
