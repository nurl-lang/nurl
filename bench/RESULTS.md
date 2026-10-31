# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T09:28:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1014-aws x86_64` |
| CPU | Intel(R) Xeon(R) 6975P-C (4 logical cores) |
| Memory | 16077560 KiB |
| Commit | `c8515d007ba9c7df3d78feeccc7a30fcca592b0e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41188458808 |
| NURL | `v0.82.0-19-gc8515d00` |
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
| _(floor: empty program)_ | _2.464_ | _2.354_ | _2.487_ | _20.377_ | _10.516_ |
| `lcg` | 34.046 | **33.997** | 34.069 | 1112.522 | 3290.882 |
| `packet_classifier` | 57.964 | **57.847** | 58.015 | 140.539 | 2618.254 |
| `ring_write` | **36.910** | 37.348 | 36.931 | 57.549 | 4029.774 |
| `histogram_bins` | 35.472 | 35.294 | **35.292** | 58.367 | 3654.820 |
| `prefix_scan` | 19.686 | **19.545** | 19.612 | 54.820 | 2674.240 |
| `binary_search` | 31.119 | **25.231** | 32.865 | 92.784 | 4212.024 |
| `sort_window` | 34.049 | **34.044** | 34.888 | 145.751 | 7940.995 |
| `bloom_filter` | 12.956 | **12.843** | 12.868 | 1948.818 | 4774.549 |
| `hash_join` | 20.643 | **20.476** | 22.317 | 2444.100 | 5261.889 |
| `sieve` | 39.357 | **38.815** | 38.899 | 78.230 | 2176.843 |
| `fib` | **20.168** | 23.484 | 23.634 | 94.900 | 664.014 |
| `collatz` | **13.586** | 13.661 | 14.534 | 51.000 | 444.836 |
| `matmul` | 17.353 | 17.209 | **17.191** | 55.597 | 2120.836 |
| `json_parse` | **6.749** | 8.336 | 11.037 | 27.646 | 24.547 |
| `nbody` | **18.359** | 25.915 | 19.084 | 65.457 | 1747.356 |
| `chacha20` | **7.803** | 31.264 | 27.272 | n/a | n/a |
| `poly1305` | **11.662** | 29.039 | 21.322 | n/a | n/a |
| `blake2b` | **35.816** | 39.999 | 44.219 | n/a | n/a |
| `sha512` | **35.333** | 35.872 | 42.645 | n/a | n/a |
| `x25519` | **24.446** | 34.988 | 34.447 | n/a | n/a |

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
| _(floor: empty program)_ | _4.616_ | _83.480_ | _**88.096**_ | _46.487_ | _53.809_ | _48.156_ |
| `lcg` | 4.917 | 94.196 | **99.113** | 48.256 | 61.711 | 54.463 |
| `packet_classifier` | 5.237 | 97.873 | **103.110** | 49.185 | 62.610 | 53.253 |
| `ring_write` | 12.511 | 98.369 | **110.880** | 55.721 | 65.739 | 53.097 |
| `histogram_bins` | 12.674 | 98.038 | **110.712** | 55.543 | 97.114 | 59.300 |
| `prefix_scan` | 12.819 | 103.435 | **116.254** | 56.681 | 72.975 | 59.499 |
| `binary_search` | 12.738 | 100.575 | **113.313** | 56.426 | 68.736 | 58.980 |
| `sort_window` | 12.880 | 101.066 | **113.946** | 56.535 | 74.699 | 63.016 |
| `bloom_filter` | 12.987 | 99.165 | **112.152** | 55.452 | 69.128 | 59.478 |
| `hash_join` | 15.438 | 186.240 | **201.678** | 60.510 | 149.502 | 97.376 |
| `sieve` | 12.663 | 98.992 | **111.655** | 56.718 | 74.124 | 64.360 |
| `fib` | 5.169 | 95.402 | **100.571** | 48.634 | 63.044 | 54.206 |
| `collatz` | 5.199 | 96.371 | **101.570** | 48.354 | 62.842 | 52.948 |
| `matmul` | 12.762 | 99.359 | **112.121** | 55.658 | 75.377 | 71.039 |
| `json_parse` | 37.474 | 317.610 | **355.084** | 83.635 | 114.212 | 139.739 |
| `nbody` | 14.011 | 103.796 | **117.807** | 58.644 | 90.650 | 83.980 |
| `chacha20` | 40.888 | 541.576 | **582.464** | 86.695 | 101.072 | 93.705 |
| `poly1305` | 32.790 | 362.067 | **394.857** | 78.553 | 105.397 | 104.115 |
| `blake2b` | 28.611 | 245.346 | **273.957** | 75.095 | 104.414 | 102.565 |
| `sha512` | 28.809 | 322.727 | **351.536** | 74.980 | 101.593 | 89.647 |
| `x25519` | 38.034 | 1097.981 | **1136.015** | 85.055 | 890.535 | 388.574 |

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
