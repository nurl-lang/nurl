# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T18:19:17Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `718b22961e4a5919e8de4f89188b9a84f42fa870` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41105271113 |
| NURL | `v0.81.0-6-g718b2296` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.1 |
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
| _(floor: empty program)_ | _2.834_ | _2.694_ | _2.898_ | _20.089_ | _10.852_ |
| `lcg` | 31.246 | 31.000 | **30.913** | 1158.181 | 2862.655 |
| `packet_classifier` | 43.116 | 43.242 | **42.174** | 129.242 | 2409.306 |
| `ring_write` | 29.888 | 29.594 | **29.581** | 52.625 | 3463.012 |
| `histogram_bins` | **31.266** | 31.273 | 31.509 | 55.055 | 3148.976 |
| `prefix_scan` | 18.025 | 17.926 | **17.834** | 46.738 | 2306.439 |
| `binary_search` | 16.957 | **16.640** | 17.424 | 73.780 | 3669.657 |
| `sort_window` | 22.360 | **22.144** | 22.480 | 139.105 | 6831.495 |
| `bloom_filter` | 10.692 | **10.448** | 10.584 | 1574.486 | 4107.750 |
| `hash_join` | **17.344** | 17.449 | 19.912 | 1934.084 | 4468.486 |
| `sieve` | 17.692 | **17.471** | 17.535 | 53.201 | 1667.551 |
| `fib` | 21.913 | **21.665** | 21.902 | 82.252 | 560.090 |
| `collatz` | 11.127 | **11.043** | 11.322 | 41.036 | 395.129 |
| `matmul` | **22.027** | 22.345 | 22.549 | 53.355 | 1527.213 |
| `json_parse` | **6.883** | 8.782 | 12.216 | 29.708 | 24.495 |
| `nbody` | **18.345** | 27.524 | 19.884 | 63.038 | 1372.470 |
| `chacha20` | **9.069** | 22.230 | 21.881 | n/a | n/a |
| `poly1305` | **10.882** | 29.302 | 18.079 | n/a | n/a |
| `blake2b` | **28.846** | 46.453 | 51.099 | n/a | n/a |
| `sha512` | 32.968 | **32.622** | 35.364 | n/a | n/a |
| `x25519` | **20.981** | 32.967 | 33.080 | n/a | n/a |

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
| _(floor: empty program)_ | _5.459_ | _94.271_ | _**99.730**_ | _52.841_ | _68.960_ | _52.015_ |
| `lcg` | 5.616 | 94.774 | **100.390** | 51.044 | 71.386 | 59.108 |
| `packet_classifier` | 5.436 | 94.814 | **100.250** | 50.087 | 78.443 | 60.699 |
| `ring_write` | 12.070 | 98.517 | **110.587** | 57.858 | 76.914 | 61.654 |
| `histogram_bins` | 12.143 | 99.627 | **111.770** | 57.879 | 97.851 | 67.343 |
| `prefix_scan` | 12.143 | 100.126 | **112.269** | 59.965 | 80.577 | 62.132 |
| `binary_search` | 12.683 | 102.535 | **115.218** | 59.211 | 78.507 | 65.662 |
| `sort_window` | 12.400 | 102.726 | **115.126** | 58.905 | 81.496 | 96.737 |
| `bloom_filter` | 13.418 | 108.473 | **121.891** | 62.453 | 87.236 | 67.442 |
| `hash_join` | 14.464 | 176.353 | **190.817** | 60.862 | 143.081 | 97.129 |
| `sieve` | 13.038 | 108.311 | **121.349** | 63.717 | 90.597 | 75.553 |
| `fib` | 6.030 | 105.668 | **111.698** | 56.639 | 85.237 | 64.961 |
| `collatz` | 6.124 | 108.801 | **114.925** | 56.043 | 83.307 | 64.591 |
| `matmul` | 13.570 | 105.736 | **119.306** | 63.001 | 90.689 | 79.731 |
| `json_parse` | 34.118 | 295.728 | **329.846** | 84.038 | 123.290 | 137.236 |
| `nbody` | 13.992 | 112.315 | **126.307** | 62.962 | 101.229 | 89.209 |
| `chacha20` | 37.267 | 504.221 | **541.488** | 87.407 | 114.445 | 103.839 |
| `poly1305` | 31.264 | 346.555 | **377.819** | 83.306 | 117.144 | 110.185 |
| `blake2b` | 27.363 | 237.183 | **264.546** | 79.678 | 117.857 | 108.432 |
| `sha512` | 27.880 | 306.902 | **334.782** | 79.354 | 114.931 | 99.946 |
| `x25519` | 35.643 | 950.164 | **985.807** | 86.487 | 752.226 | 337.594 |

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
