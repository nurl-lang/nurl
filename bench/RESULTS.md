# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-21T15:48:19Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366624 KiB |
| Commit | `749924828f64b4670ee452f7f08f44261cf1f413` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44920458307 |
| NURL | `v0.94.0` |
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
| _(floor: empty program)_ | _3.704_ | _3.637_ | _3.889_ | _30.676_ | _16.051_ |
| `lcg` | **46.524** | 46.613 | 46.751 | 1907.560 | 4960.512 |
| `packet_classifier` | 66.004 | **65.955** | 66.225 | 165.731 | 4500.554 |
| `ring_write` | 50.153 | **50.086** | 50.371 | 79.716 | 6346.377 |
| `histogram_bins` | 47.019 | **46.871** | 47.227 | 82.182 | 6144.869 |
| `prefix_scan` | 26.815 | **26.657** | 26.927 | 74.729 | 4429.424 |
| `binary_search` | 43.801 | 43.705 | **39.032** | 117.322 | 6156.123 |
| `sort_window` | 32.516 | **32.420** | 32.659 | 163.811 | 11311.866 |
| `bloom_filter` | **19.673** | 21.107 | 23.014 | 2857.419 | 7179.015 |
| `hash_join` | 29.274 | **29.045** | 32.526 | 3410.126 | 7287.149 |
| `sieve` | 26.968 | 30.643 | **26.717** | 78.365 | 3338.127 |
| `fib` | 35.791 | 35.683 | **30.502** | 151.688 | 1068.481 |
| `collatz` | **15.995** | 16.130 | 16.331 | 58.241 | 734.933 |
| `matmul` | **47.773** | 48.672 | 49.768 | 80.588 | 3180.152 |
| `json_parse` | **8.313** | 14.157 | 19.874 | 44.774 | 38.337 |
| `nbody` | **28.272** | 52.877 | 29.129 | 98.953 | 3195.528 |
| `safe_record_array` | 64.403 | **62.730** | 72.873 | n/a | n/a |
| `payload_state_machine` | 85.420 | 83.074 | **82.939** | n/a | n/a |
| `captured_closure_queue` | 99.532 | **96.719** | 114.250 | n/a | n/a |
| `dynamic_method_mix` | 136.856 | **130.915** | 161.261 | n/a | n/a |
| `csv_table_pipeline` | **93.552** | 107.622 | 97.528 | n/a | n/a |
| `chacha20` | **11.111** | 44.052 | 38.324 | n/a | n/a |
| `poly1305` | **14.825** | 25.798 | 26.134 | n/a | n/a |
| `blake2b` | **49.973** | 73.328 | 80.700 | n/a | n/a |
| `sha512` | 52.495 | **52.083** | 57.113 | n/a | n/a |
| `x25519` | **39.407** | 57.218 | 58.561 | n/a | n/a |

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
| _(floor: empty program)_ | _7.710_ | _78.601_ | _**86.311**_ | _34.857_ | _45.865_ | _77.484_ |
| `lcg` | 7.994 | 85.026 | **93.020** | 35.010 | 51.905 | 80.153 |
| `packet_classifier` | 8.186 | 85.997 | **94.183** | 35.330 | 53.824 | 79.816 |
| `ring_write` | 15.342 | 87.184 | **102.526** | 42.391 | 54.087 | 81.519 |
| `histogram_bins` | 15.507 | 88.741 | **104.248** | 43.056 | 76.926 | 90.416 |
| `prefix_scan` | 15.736 | 88.351 | **104.087** | 42.633 | 57.378 | 85.373 |
| `binary_search` | 15.793 | 86.668 | **102.461** | 42.816 | 54.659 | 86.935 |
| `sort_window` | 15.749 | 88.859 | **104.608** | 42.681 | 61.054 | 92.086 |
| `bloom_filter` | 16.334 | 88.991 | **105.325** | 43.189 | 60.034 | 87.978 |
| `hash_join` | 20.100 | 153.239 | **173.339** | 47.374 | 122.638 | 134.490 |
| `sieve` | 15.698 | 88.797 | **104.495** | 43.286 | 63.114 | 94.734 |
| `fib` | 8.269 | 85.835 | **94.104** | 35.784 | 53.271 | 81.456 |
| `collatz` | 8.384 | 87.290 | **95.674** | 35.487 | 54.169 | 81.344 |
| `matmul` | 15.908 | 87.989 | **103.897** | 42.876 | 63.938 | 103.375 |
| `json_parse` | 50.325 | 220.792 | **271.117** | 77.945 | 98.412 | 188.135 |
| `nbody` | 17.648 | 93.720 | **111.368** | 45.167 | 78.524 | 121.114 |
| `safe_record_array` | 19.647 | 193.010 | **212.657** | 46.882 | 64.295 | 108.094 |
| `payload_state_machine` | 29.053 | 158.060 | **187.113** | 56.522 | 68.275 | 112.887 |
| `captured_closure_queue` | 23.807 | 227.769 | **251.576** | 51.464 | 76.223 | 139.851 |
| `dynamic_method_mix` | 23.754 | 226.330 | **250.084** | 51.565 | 77.763 | 130.591 |
| `csv_table_pipeline` | 90.260 | 480.761 | **571.021** | 117.767 | 189.311 | 285.875 |
| `chacha20` | 70.872 | 425.013 | **495.885** | 98.695 | 86.889 | 132.627 |
| `poly1305` | 59.055 | 258.901 | **317.956** | 86.531 | 90.005 | 146.830 |
| `blake2b` | 38.207 | 216.963 | **255.170** | 66.225 | 86.129 | 141.973 |
| `sha512` | 37.564 | 304.125 | **341.689** | 65.156 | 86.223 | 129.012 |
| `x25519` | 55.377 | 1052.179 | **1107.556** | 83.156 | 946.452 | 528.888 |

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
