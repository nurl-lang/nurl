# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-04T09:13:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1014-aws x86_64` |
| CPU | Intel(R) Xeon(R) 6975P-C (4 logical cores) |
| Memory | 16077556 KiB |
| Commit | `9d2e7cdf173b47d8d81cdad4d3f908987240f9c2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41804902538 |
| NURL | `v0.86.0-8-g9d2e7cdf` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.0 |
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
| _(floor: empty program)_ | _2.381_ | _2.331_ | _2.439_ | _19.745_ | _10.393_ |
| `lcg` | 33.709 | **33.538** | 33.630 | 1101.890 | 3266.243 |
| `packet_classifier` | 57.386 | **57.223** | 57.306 | 136.042 | 2649.117 |
| `ring_write` | 36.582 | 36.885 | **36.294** | 54.336 | 4040.865 |
| `histogram_bins` | **34.674** | 34.781 | 34.785 | 55.858 | 3722.247 |
| `prefix_scan` | 19.391 | **19.202** | 19.303 | 50.674 | 2603.343 |
| `binary_search` | 31.419 | **24.949** | 32.489 | 89.131 | 4432.311 |
| `sort_window` | 33.675 | **33.435** | 34.348 | 141.086 | 7384.157 |
| `bloom_filter` | 12.943 | **12.699** | 12.817 | 1931.607 | 4957.976 |
| `hash_join` | 20.398 | **20.173** | 21.874 | 2424.279 | 5262.780 |
| `sieve` | 37.596 | **36.557** | 36.981 | 73.926 | 2093.782 |
| `fib` | **19.886** | 23.132 | 23.331 | 91.146 | 662.251 |
| `collatz` | 13.520 | **13.484** | 14.527 | 50.510 | 444.266 |
| `matmul` | 17.033 | **16.987** | 17.056 | 54.947 | 1852.810 |
| `json_parse` | **5.357** | 8.261 | 10.935 | 25.692 | 24.051 |
| `nbody` | **18.324** | 25.689 | 18.933 | 63.399 | 1746.194 |
| `chacha20` | **5.171** | 30.907 | 26.991 | n/a | n/a |
| `poly1305` | **9.447** | 28.947 | 21.168 | n/a | n/a |
| `blake2b` | **35.668** | 39.624 | 43.888 | n/a | n/a |
| `sha512` | **35.195** | 35.810 | 41.736 | n/a | n/a |
| `x25519` | **24.051** | 34.452 | 34.169 | n/a | n/a |

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
| _(floor: empty program)_ | _4.456_ | _79.534_ | _**83.990**_ | _42.804_ | _49.973_ | _45.246_ |
| `lcg` | 4.608 | 84.559 | **89.167** | 40.071 | 51.224 | 50.228 |
| `packet_classifier` | 4.728 | 88.819 | **93.547** | 42.064 | 53.888 | 48.741 |
| `ring_write` | 10.587 | 88.281 | **98.868** | 47.328 | 54.926 | 51.307 |
| `histogram_bins` | 10.739 | 87.616 | **98.355** | 47.114 | 87.427 | 53.908 |
| `prefix_scan` | 10.714 | 86.773 | **97.487** | 48.355 | 58.052 | 50.995 |
| `binary_search` | 10.768 | 88.594 | **99.362** | 47.754 | 54.500 | 52.258 |
| `sort_window` | 11.463 | 96.323 | **107.786** | 52.533 | 65.207 | 59.426 |
| `bloom_filter` | 11.576 | 94.070 | **105.646** | 50.528 | 63.301 | 54.000 |
| `hash_join` | 13.716 | 172.104 | **185.820** | 54.159 | 136.286 | 91.845 |
| `sieve` | 11.113 | 90.003 | **101.116** | 49.892 | 63.813 | 60.961 |
| `fib` | 4.716 | 87.343 | **92.059** | 42.600 | 56.084 | 49.165 |
| `collatz` | 4.760 | 87.692 | **92.452** | 41.504 | 55.648 | 48.708 |
| `matmul` | 11.187 | 92.052 | **103.239** | 50.580 | 67.967 | 65.901 |
| `json_parse` | 32.005 | 232.320 | **264.325** | 75.084 | 102.200 | 138.296 |
| `nbody` | 12.044 | 94.273 | **106.317** | 50.208 | 80.927 | 78.703 |
| `chacha20` | 44.491 | 490.386 | **534.877** | 90.018 | 92.666 | 87.678 |
| `poly1305` | 36.840 | 286.269 | **323.109** | 78.768 | 96.212 | 99.365 |
| `blake2b` | 25.555 | 239.853 | **265.408** | 68.344 | 96.428 | 98.147 |
| `sha512` | 24.730 | 314.730 | **339.460** | 68.917 | 91.492 | 86.126 |
| `x25519` | 34.851 | 990.665 | **1025.516** | 80.093 | 883.270 | 385.561 |

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
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
