# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T07:36:08Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `6468fc153d3fb6c50e81d26ae2e7a4c2d25f217e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40650407226 |
| NURL | `v0.79.1-25-g6468fc15` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.3 |
| Python | Python 3.12.3 |

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
| _(floor: empty program)_ | _1.483_ | _1.474_ | _1.711_ | _23.519_ | _18.458_ |
| `lcg` | **39.335** | 39.346 | 39.393 | 1905.727 | 5082.536 |
| `packet_classifier` | 56.550 | **56.514** | 56.769 | 163.640 | 4424.768 |
| `ring_write` | 42.417 | **42.373** | 42.736 | 67.710 | 6487.711 |
| `histogram_bins` | **39.757** | 40.880 | 41.253 | 68.949 | 6077.128 |
| `prefix_scan` | 21.968 | **21.823** | 22.057 | 66.436 | 4507.983 |
| `binary_search` | 39.970 | **38.567** | 41.347 | 108.924 | 6188.969 |
| `sort_window` | 26.872 | **26.805** | 27.056 | 198.832 | 14664.657 |
| `bloom_filter` | **16.791** | 17.971 | 18.448 | 2845.975 | 7809.234 |
| `hash_join` | **27.139** | 28.280 | 29.548 | 3456.706 | 8357.941 |
| `sieve` | 21.271 | **20.885** | 21.711 | 68.992 | 3284.986 |
| `fib` | **25.502** | 29.980 | 30.382 | 133.263 | 1361.416 |
| `collatz` | 12.392 | **12.339** | 12.653 | 53.264 | 760.257 |
| `matmul` | 33.679 | **33.649** | 34.095 | 78.469 | 3042.986 |
| `json_parse` | 9.003 | **9.001** | 12.398 | 40.547 | 42.927 |
| `nbody` | **25.541** | 40.066 | 25.629 | 103.352 | 3143.035 |
| `chacha20` | **7.719** | 42.408 | 33.963 | n/a | n/a |
| `poly1305` | **12.081** | 32.108 | 21.392 | n/a | n/a |
| `blake2b` | **43.861** | 65.134 | 69.377 | n/a | n/a |
| `sha512` | **47.598** | 50.813 | 49.968 | n/a | n/a |
| `x25519` | **31.742** | 48.847 | 49.702 | n/a | n/a |

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
| _(floor: empty program)_ | _5.158_ | _120.409_ | _**125.567**_ | _64.133_ | _87.867_ | _56.993_ |
| `lcg` | 4.653 | 133.037 | **137.690** | 64.883 | 93.330 | 60.100 |
| `packet_classifier` | 4.842 | 134.161 | **139.003** | 64.780 | 93.551 | 60.620 |
| `ring_write` | 15.394 | 132.498 | **147.892** | 74.066 | 95.406 | 62.157 |
| `histogram_bins` | 15.861 | 137.619 | **153.480** | 76.070 | 114.195 | 69.701 |
| `prefix_scan` | 15.778 | 136.606 | **152.384** | 75.858 | 101.812 | 65.671 |
| `binary_search` | 16.139 | 135.812 | **151.951** | 76.073 | 97.380 | 65.587 |
| `sort_window` | 16.231 | 135.839 | **152.070** | 76.128 | 107.427 | 71.525 |
| `bloom_filter` | 16.456 | 138.969 | **155.425** | 75.714 | 108.555 | 68.750 |
| `hash_join` | 20.822 | 273.706 | **294.528** | 80.192 | 227.624 | 114.532 |
| `sieve` | 16.148 | 135.780 | **151.928** | 75.643 | 110.054 | 76.401 |
| `fib` | 5.015 | 135.079 | **140.094** | 66.600 | 94.403 | 61.092 |
| `collatz` | 5.166 | 137.202 | **142.368** | 67.174 | 97.567 | 63.928 |
| `matmul` | 17.713 | 139.507 | **157.220** | 77.807 | 111.421 | 81.531 |
| `json_parse` | 53.118 | 514.234 | **567.352** | 116.381 | 170.544 | 165.411 |
| `nbody` | 19.500 | 149.991 | **169.491** | 81.821 | 135.943 | 101.999 |
| `chacha20` | 59.908 | 802.353 | **862.261** | 121.910 | 147.804 | 112.300 |
| `poly1305` | 46.150 | 527.982 | **574.132** | 107.471 | 149.426 | 124.261 |
| `blake2b` | 40.273 | 389.862 | **430.135** | 100.959 | 151.615 | 117.693 |
| `sha512` | 40.999 | 489.518 | **530.517** | 101.334 | 144.735 | 104.067 |
| `x25519` | 54.509 | 1221.530 | **1276.039** | 116.764 | 1267.989 | 506.588 |

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
