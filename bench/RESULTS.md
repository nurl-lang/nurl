# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-22T09:49:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16365616 KiB |
| Commit | `1b69f7531b952ceffffd5be85a62dcaf563b3759` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45008919842 |
| NURL | `v0.94.0-22-g1b69f753` |
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
| _(floor: empty program)_ | _2.261_ | _2.224_ | _2.295_ | _19.060_ | _9.766_ |
| `lcg` | 31.197 | **31.093** | 31.243 | 1036.932 | 3063.405 |
| `packet_classifier` | 53.127 | **53.037** | 53.161 | 126.566 | 2447.414 |
| `ring_write` | 39.199 | 39.796 | **39.148** | 59.495 | 4059.726 |
| `histogram_bins` | 32.369 | **32.180** | 32.256 | 51.999 | 3330.115 |
| `prefix_scan` | 17.895 | **17.794** | 17.982 | 48.357 | 2484.927 |
| `binary_search` | 28.649 | 28.728 | **23.348** | 83.329 | 3970.046 |
| `sort_window` | **31.025** | 31.103 | 31.755 | 132.284 | 7230.756 |
| `bloom_filter` | 11.907 | **11.809** | 12.004 | 1829.851 | 4714.785 |
| `hash_join` | 18.892 | **18.640** | 20.301 | 2256.682 | 5109.727 |
| `sieve` | 36.274 | 36.376 | **35.966** | 68.660 | 2030.544 |
| `fib` | 21.497 | 21.488 | **18.615** | 85.756 | 613.259 |
| `collatz` | 13.321 | 13.234 | **13.214** | 45.141 | 409.765 |
| `matmul` | 16.444 | **16.040** | 16.170 | 51.114 | 1796.155 |
| `json_parse` | **5.006** | 7.828 | 10.196 | 24.413 | 22.865 |
| `nbody` | 17.793 | 26.035 | **17.467** | 62.345 | 1700.117 |
| `safe_record_array` | 46.217 | **44.611** | 47.393 | n/a | n/a |
| `payload_state_machine` | 60.786 | 61.002 | **58.567** | n/a | n/a |
| `captured_closure_queue` | 70.179 | **66.670** | 82.810 | n/a | n/a |
| `dynamic_method_mix` | 88.810 | 89.523 | **88.673** | n/a | n/a |
| `csv_table_pipeline` | **61.194** | 67.213 | 65.466 | n/a | n/a |
| `chacha20` | **4.690** | 26.335 | 25.049 | n/a | n/a |
| `poly1305` | **9.272** | 19.653 | 19.596 | n/a | n/a |
| `blake2b` | **31.959** | 37.801 | 41.532 | n/a | n/a |
| `sha512` | **32.175** | 33.125 | 38.556 | n/a | n/a |
| `x25519` | **22.210** | 31.954 | 31.637 | n/a | n/a |

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
| _(floor: empty program)_ | _4.360_ | _44.929_ | _**49.289**_ | _17.999_ | _21.870_ | _43.780_ |
| `lcg` | 4.511 | 49.840 | **54.351** | 19.090 | 26.059 | 47.852 |
| `packet_classifier` | 4.800 | 50.491 | **55.291** | 19.216 | 26.552 | 47.801 |
| `ring_write` | 9.332 | 51.292 | **60.624** | 23.272 | 27.315 | 48.482 |
| `histogram_bins` | 9.367 | 51.343 | **60.710** | 23.071 | 43.047 | 54.648 |
| `prefix_scan` | 9.788 | 51.716 | **61.504** | 23.429 | 29.303 | 50.755 |
| `binary_search` | 9.522 | 51.799 | **61.321** | 23.601 | 27.639 | 52.850 |
| `sort_window` | 9.851 | 52.706 | **62.557** | 23.702 | 32.011 | 57.371 |
| `bloom_filter` | 10.130 | 52.439 | **62.569** | 24.270 | 31.032 | 53.645 |
| `hash_join` | 12.040 | 94.135 | **106.175** | 26.079 | 72.062 | 85.640 |
| `sieve` | 9.440 | 52.581 | **62.021** | 23.590 | 32.556 | 58.454 |
| `fib` | 5.059 | 51.449 | **56.508** | 18.950 | 26.826 | 47.014 |
| `collatz` | 4.863 | 51.674 | **56.537** | 18.509 | 26.489 | 47.936 |
| `matmul` | 9.651 | 52.925 | **62.576** | 23.305 | 32.954 | 63.799 |
| `json_parse` | 32.106 | 151.589 | **183.695** | 46.139 | 56.899 | 125.178 |
| `nbody` | 10.506 | 56.867 | **67.373** | 24.925 | 43.044 | 75.572 |
| `safe_record_array` | 11.748 | 132.047 | **143.795** | 26.133 | 34.587 | 68.735 |
| `payload_state_machine` | 18.198 | 103.318 | **121.516** | 32.672 | 36.368 | 71.600 |
| `captured_closure_queue` | 15.095 | 157.085 | **172.180** | 29.631 | 41.871 | 88.648 |
| `dynamic_method_mix` | 14.458 | 153.751 | **168.209** | 28.945 | 40.024 | 84.118 |
| `csv_table_pipeline` | 58.068 | 341.373 | **399.441** | 74.322 | 122.149 | 193.483 |
| `chacha20` | 43.080 | 289.125 | **332.205** | 58.424 | 49.531 | 84.894 |
| `poly1305` | 35.396 | 172.101 | **207.497** | 50.070 | 50.867 | 94.292 |
| `blake2b` | 24.184 | 147.976 | **172.160** | 39.100 | 50.832 | 93.745 |
| `sha512` | 23.322 | 205.411 | **228.733** | 37.844 | 49.115 | 82.466 |
| `x25519` | 32.856 | 713.197 | **746.053** | 48.709 | 638.427 | 361.857 |

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
