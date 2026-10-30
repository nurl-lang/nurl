# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T03:46:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16366504 KiB |
| Commit | `88b44aa72c4bccfa928d76e7541f405912ed0ff4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40998724431 |
| NURL | `v0.80.0-102-g88b44aa7` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.4 |
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
| _(floor: empty program)_ | _1.416_ | _1.389_ | _1.607_ | _20.137_ | _14.154_ |
| `lcg` | 35.430 | **35.429** | 35.597 | 1221.634 | 3549.575 |
| `packet_classifier` | 61.153 | **61.101** | 61.371 | 148.519 | 2968.091 |
| `ring_write` | 38.526 | 39.083 | **38.520** | 60.990 | 4309.053 |
| `histogram_bins` | **36.763** | 36.812 | 36.808 | 61.736 | 4047.475 |
| `prefix_scan` | 19.630 | **19.564** | 20.001 | 61.218 | 3110.454 |
| `binary_search` | 32.255 | **26.371** | 34.449 | 99.758 | 4880.128 |
| `sort_window` | 35.683 | **35.615** | 36.608 | 161.434 | 7716.900 |
| `bloom_filter` | 12.671 | **12.654** | 12.759 | 2110.216 | 5526.301 |
| `hash_join` | **21.350** | 21.991 | 22.514 | 2579.121 | 6177.243 |
| `sieve` | 39.551 | **38.002** | 38.170 | 81.105 | 2303.318 |
| `fib` | **20.403** | 24.049 | 24.255 | 100.034 | 783.573 |
| `collatz` | **13.353** | 13.509 | 14.730 | 56.047 | 498.505 |
| `matmul` | 17.498 | **17.381** | 17.632 | 67.346 | 2172.016 |
| `json_parse` | **5.938** | 6.968 | 8.399 | 29.481 | 30.172 |
| `nbody` | **19.231** | 26.946 | 19.612 | 75.074 | 1903.026 |
| `chacha20` | **7.245** | 32.770 | 28.428 | n/a | n/a |
| `poly1305` | **11.739** | 30.416 | 22.040 | n/a | n/a |
| `blake2b` | **37.782** | 45.790 | 47.865 | n/a | n/a |
| `sha512` | **37.004** | 41.172 | 44.268 | n/a | n/a |
| `x25519` | **25.282** | 36.655 | 36.017 | n/a | n/a |

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
| _(floor: empty program)_ | _4.119_ | _100.936_ | _**105.055**_ | _55.121_ | _72.812_ | _56.106_ |
| `lcg` | 4.088 | 110.274 | **114.362** | 54.706 | 76.009 | 62.665 |
| `packet_classifier` | 4.214 | 110.705 | **114.919** | 57.998 | 78.902 | 63.102 |
| `ring_write` | 12.740 | 110.198 | **122.938** | 61.936 | 76.371 | 63.541 |
| `histogram_bins` | 13.057 | 110.024 | **123.081** | 62.882 | 90.440 | 70.835 |
| `prefix_scan` | 12.981 | 112.857 | **125.838** | 63.589 | 84.681 | 69.631 |
| `binary_search` | 13.101 | 116.417 | **129.518** | 64.880 | 81.189 | 68.885 |
| `sort_window` | 13.212 | 114.786 | **127.998** | 64.359 | 90.423 | 75.843 |
| `bloom_filter` | 13.516 | 117.833 | **131.349** | 65.590 | 90.141 | 71.962 |
| `hash_join` | 16.431 | 207.920 | **224.351** | 67.364 | 169.893 | 109.162 |
| `sieve` | 12.991 | 109.024 | **122.015** | 62.677 | 87.085 | 75.599 |
| `fib` | 4.176 | 108.203 | **112.379** | 55.039 | 79.042 | 62.427 |
| `collatz` | 4.399 | 110.646 | **115.045** | 56.185 | 80.584 | 64.444 |
| `matmul` | 13.791 | 110.159 | **123.950** | 63.512 | 90.706 | 83.881 |
| `json_parse` | 39.839 | 364.789 | **404.628** | 91.694 | 131.126 | 156.604 |
| `nbody` | 14.723 | 119.419 | **134.142** | 66.121 | 107.556 | 96.257 |
| `chacha20` | 44.580 | 594.432 | **639.012** | 96.674 | 120.060 | 109.269 |
| `poly1305` | 34.305 | 407.863 | **442.168** | 87.854 | 121.511 | 120.232 |
| `blake2b` | 31.499 | 306.188 | **337.687** | 85.396 | 123.808 | 118.326 |
| `sha512` | 31.324 | 373.386 | **404.710** | 82.504 | 117.372 | 104.194 |
| `x25519` | 41.400 | 1034.248 | **1075.648** | 92.431 | 1005.892 | 430.017 |

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
