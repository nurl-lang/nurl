# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-17T10:47:47Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16365628 KiB |
| Commit | `f674f7d3894c251efb4c6dc16c4626bcd75c68f1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44067109449 |
| NURL | `v0.92.1-22-gf674f7d3` |
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
| _(floor: empty program)_ | _2.727_ | _2.617_ | _2.782_ | _27.097_ | _14.126_ |
| `lcg` | 42.555 | **42.277** | 42.938 | 1391.839 | 4101.857 |
| `packet_classifier` | 70.787 | **68.833** | 69.680 | 173.312 | 3220.608 |
| `ring_write` | 45.415 | **44.760** | 46.456 | 69.761 | 5134.658 |
| `histogram_bins` | 43.584 | 43.007 | **42.884** | 70.815 | 4707.632 |
| `prefix_scan` | **24.314** | 24.557 | 24.517 | 67.812 | 3272.489 |
| `binary_search` | 41.413 | 40.892 | **33.412** | 116.048 | 5089.968 |
| `sort_window` | **42.019** | 42.185 | 43.586 | 184.842 | 9858.818 |
| `bloom_filter` | 15.894 | **15.694** | 15.905 | 2376.561 | 6008.902 |
| `hash_join` | 25.962 | **24.613** | 27.250 | 3023.770 | 6519.013 |
| `sieve` | **40.181** | 42.245 | 41.151 | 88.085 | 2534.967 |
| `fib` | 30.628 | 30.749 | **29.772** | 118.496 | 844.149 |
| `collatz` | 18.307 | **17.565** | 18.225 | 65.979 | 580.588 |
| `matmul` | 23.366 | **23.100** | 23.284 | 76.149 | 2390.624 |
| `json_parse` | **6.807** | 10.763 | 13.810 | 36.309 | 32.936 |
| `nbody` | **24.573** | 36.446 | 24.713 | 84.281 | 2221.928 |
| `safe_record_array` | 67.206 | **64.115** | 67.756 | n/a | n/a |
| `payload_state_machine` | 86.208 | **85.456** | 86.055 | n/a | n/a |
| `captured_closure_queue` | 95.740 | **90.942** | 112.682 | n/a | n/a |
| `dynamic_method_mix` | 123.847 | 123.577 | **122.641** | n/a | n/a |
| `csv_table_pipeline` | **89.099** | 99.525 | 94.431 | n/a | n/a |
| `chacha20` | **6.523** | 36.303 | 34.255 | n/a | n/a |
| `poly1305` | **12.001** | 25.026 | 25.055 | n/a | n/a |
| `blake2b` | **44.224** | 49.881 | 55.757 | n/a | n/a |
| `sha512` | 44.836 | **43.536** | 48.368 | n/a | n/a |
| `x25519` | **30.199** | 43.327 | 42.937 | n/a | n/a |

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
| _(floor: empty program)_ | _6.229_ | _66.626_ | _**72.855**_ | _27.539_ | _32.079_ | _52.880_ |
| `lcg` | 6.386 | 71.454 | **77.840** | 27.759 | 40.175 | 56.785 |
| `packet_classifier` | 6.615 | 70.081 | **76.696** | 26.574 | 40.427 | 57.259 |
| `ring_write` | 13.014 | 72.570 | **85.584** | 33.721 | 41.311 | 59.008 |
| `histogram_bins` | 13.215 | 75.318 | **88.533** | 34.479 | 63.671 | 66.006 |
| `prefix_scan` | 13.703 | 74.232 | **87.935** | 35.560 | 45.580 | 61.867 |
| `binary_search` | 13.511 | 73.621 | **87.132** | 34.198 | 41.941 | 63.598 |
| `sort_window` | 13.377 | 76.489 | **89.866** | 34.623 | 48.490 | 68.888 |
| `bloom_filter` | 14.468 | 78.044 | **92.512** | 36.753 | 49.340 | 66.568 |
| `hash_join` | 17.373 | 133.772 | **151.145** | 38.982 | 106.156 | 111.164 |
| `sieve` | 13.626 | 75.326 | **88.952** | 35.773 | 49.991 | 71.216 |
| `fib` | 6.606 | 73.047 | **79.653** | 28.183 | 42.509 | 58.811 |
| `collatz` | 6.983 | 73.194 | **80.177** | 28.743 | 42.819 | 60.931 |
| `matmul` | 14.488 | 76.491 | **90.979** | 36.280 | 54.384 | 82.795 |
| `json_parse` | 45.759 | 214.451 | **260.210** | 67.817 | 85.492 | 163.860 |
| `nbody` | 15.885 | 81.079 | **96.964** | 37.502 | 67.275 | 95.168 |
| `safe_record_array` | 17.212 | 186.324 | **203.536** | 39.626 | 52.963 | 85.240 |
| `payload_state_machine` | 26.980 | 150.527 | **177.507** | 49.567 | 56.600 | 93.404 |
| `captured_closure_queue` | 21.078 | 218.797 | **239.875** | 43.455 | 62.448 | 112.629 |
| `dynamic_method_mix` | 20.357 | 218.405 | **238.762** | 42.575 | 61.061 | 107.746 |
| `csv_table_pipeline` | 82.747 | 482.607 | **565.354** | 105.757 | 179.318 | 263.305 |
| `chacha20` | 62.682 | 408.728 | **471.410** | 85.344 | 74.446 | 108.637 |
| `poly1305` | 50.983 | 245.254 | **296.237** | 73.561 | 78.835 | 123.504 |
| `blake2b` | 34.083 | 209.773 | **243.856** | 56.362 | 74.395 | 117.224 |
| `sha512` | 33.670 | 290.753 | **324.423** | 56.116 | 74.624 | 103.788 |
| `x25519` | 48.332 | 1018.033 | **1066.365** | 70.563 | 883.417 | 487.315 |

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
