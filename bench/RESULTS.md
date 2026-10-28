# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T11:07:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `dd652819972d92ebae6248e5d168b75fb6625fa0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40676809223 |
| NURL | `v0.79.1-38-gdd652819` |
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
| _(floor: empty program)_ | _1.116_ | _1.089_ | _1.242_ | _16.678_ | _11.577_ |
| `lcg` | **27.798** | 28.326 | 29.212 | 1113.594 | 3003.649 |
| `packet_classifier` | 41.797 | 41.764 | **40.219** | 128.137 | 2603.160 |
| `ring_write` | 29.187 | **28.337** | 29.419 | 47.457 | 3654.384 |
| `histogram_bins` | **27.826** | 29.361 | 29.026 | 49.450 | 3460.449 |
| `prefix_scan` | 16.184 | **16.103** | 16.655 | 46.256 | 2510.973 |
| `binary_search` | 14.612 | **14.555** | 14.995 | 67.607 | 3670.767 |
| `sort_window` | 20.721 | **20.329** | 20.696 | 137.052 | 6669.613 |
| `bloom_filter` | 8.654 | **8.501** | 8.936 | 1627.739 | 4334.504 |
| `hash_join` | **15.610** | 16.358 | 17.774 | 1898.630 | 4475.229 |
| `sieve` | 12.181 | **11.832** | 12.225 | 46.534 | 1743.356 |
| `fib` | **19.366** | 19.609 | 19.728 | 77.170 | 671.652 |
| `collatz` | 8.974 | **8.918** | 9.148 | 37.164 | 411.082 |
| `matmul` | **20.024** | 21.062 | 20.700 | 55.309 | 1708.990 |
| `json_parse` | **4.894** | 5.341 | 7.039 | 26.312 | 27.923 |
| `nbody` | **16.915** | 24.991 | 17.323 | 62.234 | 1503.948 |
| `chacha20` | **6.935** | 23.558 | 20.326 | n/a | n/a |
| `poly1305` | **8.796** | 27.241 | 15.864 | n/a | n/a |
| `blake2b` | **26.879** | 42.966 | 47.900 | n/a | n/a |
| `sha512` | **29.957** | 31.879 | 31.756 | n/a | n/a |
| `x25519` | **19.369** | 29.834 | 29.873 | n/a | n/a |

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
| _(floor: empty program)_ | _3.423_ | _80.793_ | _**84.216**_ | _46.811_ | _58.289_ | _40.839_ |
| `lcg` | 3.487 | 92.702 | **96.189** | 46.863 | 70.301 | 46.396 |
| `packet_classifier` | 3.620 | 94.107 | **97.727** | 47.465 | 71.200 | 46.760 |
| `ring_write` | 10.072 | 93.069 | **103.141** | 53.002 | 69.455 | 47.384 |
| `histogram_bins` | 10.300 | 97.575 | **107.875** | 54.475 | 79.552 | 51.497 |
| `prefix_scan` | 10.420 | 97.753 | **108.173** | 54.514 | 73.200 | 49.661 |
| `binary_search` | 10.156 | 98.323 | **108.479** | 53.636 | 72.397 | 50.962 |
| `sort_window` | 10.875 | 102.967 | **113.842** | 56.857 | 81.179 | 55.023 |
| `bloom_filter` | 10.333 | 97.127 | **107.460** | 53.827 | 76.749 | 50.665 |
| `hash_join` | 12.828 | 167.703 | **180.531** | 54.511 | 137.454 | 79.192 |
| `sieve` | 10.129 | 90.436 | **100.565** | 51.435 | 73.488 | 52.592 |
| `fib` | 3.620 | 99.966 | **103.586** | 50.221 | 72.915 | 49.093 |
| `collatz` | 3.681 | 100.743 | **104.424** | 49.147 | 76.151 | 49.718 |
| `matmul` | 10.976 | 100.271 | **111.247** | 55.632 | 80.131 | 61.859 |
| `json_parse` | 32.550 | 323.455 | **356.005** | 82.220 | 114.348 | 116.871 |
| `nbody` | 12.289 | 108.456 | **120.745** | 59.865 | 96.894 | 83.217 |
| `chacha20` | 35.366 | 480.965 | **516.331** | 81.354 | 106.002 | 82.292 |
| `poly1305` | 28.151 | 336.291 | **364.442** | 74.717 | 109.184 | 91.273 |
| `blake2b` | 25.346 | 247.012 | **272.358** | 71.968 | 109.195 | 87.648 |
| `sha512` | 24.974 | 297.896 | **322.870** | 70.343 | 105.476 | 79.837 |
| `x25519` | 31.946 | 744.789 | **776.735** | 76.634 | 752.843 | 319.312 |

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
