# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T19:11:55Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1f976b0a4aad39db7a6c28948051caefe8278668` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40008634615 |
| NURL | `v0.77.2-10-g1f976b0a` |
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
| _(floor: empty program)_ | _1.449_ | _1.416_ | _1.688_ | _23.492_ | _18.859_ |
| `lcg` | **39.125** | 39.236 | 39.403 | 1897.202 | 5424.005 |
| `packet_classifier` | 56.363 | **56.317** | 56.551 | 163.807 | 4389.745 |
| `ring_write` | **42.241** | 42.251 | 42.345 | 65.966 | 6478.857 |
| `histogram_bins` | **40.586** | 40.609 | 40.835 | 67.557 | 6000.708 |
| `prefix_scan` | **21.672** | 21.898 | 22.136 | 67.583 | 4406.703 |
| `binary_search` | **38.464** | 38.483 | 41.142 | 108.169 | 6660.917 |
| `sort_window` | 26.740 | **26.525** | 26.740 | 198.932 | 12468.742 |
| `bloom_filter` | **15.503** | 17.956 | 18.513 | 2830.596 | 7882.808 |
| `hash_join` | **27.235** | 28.180 | 29.228 | 3412.431 | 8375.717 |
| `sieve` | 18.915 | **18.163** | 18.454 | 67.228 | 3451.530 |
| `fib` | 29.984 | **29.928** | 30.110 | 133.966 | 1361.274 |
| `collatz` | 12.301 | **12.286** | 12.597 | 51.524 | 742.136 |
| `matmul` | 33.594 | **33.316** | 33.660 | 77.104 | 3294.756 |
| `json_parse` | **8.228** | 8.658 | 11.822 | 38.232 | 39.589 |
| `nbody` | 25.316 | 39.787 | **25.286** | 100.834 | 3105.923 |
| `chacha20` | **7.630** | 40.625 | 33.808 | n/a | n/a |
| `poly1305` | 23.571 | 31.976 | **21.283** | n/a | n/a |
| `blake2b` | **43.472** | 65.318 | 69.428 | n/a | n/a |
| `sha512` | **46.953** | 50.535 | 49.527 | n/a | n/a |
| `x25519` | **44.329** | 48.571 | 49.344 | n/a | n/a |

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
| _(floor: empty program)_ | _4.577_ | _115.177_ | _**119.754**_ | _64.292_ | _83.210_ | _53.440_ |
| `lcg` | 4.709 | 125.628 | **130.337** | 63.052 | 92.372 | 60.758 |
| `packet_classifier` | 4.560 | 125.386 | **129.946** | 63.249 | 95.330 | 58.944 |
| `ring_write` | 13.880 | 128.095 | **141.975** | 70.710 | 94.853 | 61.056 |
| `histogram_bins` | 13.936 | 130.482 | **144.418** | 72.651 | 111.856 | 68.578 |
| `prefix_scan` | 13.985 | 128.454 | **142.439** | 71.036 | 98.874 | 64.490 |
| `binary_search` | 14.489 | 127.444 | **141.933** | 71.769 | 95.956 | 65.268 |
| `sort_window` | 14.940 | 132.517 | **147.457** | 73.796 | 106.099 | 69.946 |
| `bloom_filter` | 14.910 | 134.170 | **149.080** | 74.180 | 101.030 | 65.543 |
| `hash_join` | 18.823 | 270.644 | **289.467** | 77.174 | 219.605 | 112.512 |
| `sieve` | 14.586 | 130.710 | **145.296** | 74.034 | 107.195 | 71.090 |
| `fib` | 5.049 | 127.988 | **133.037** | 65.580 | 93.564 | 60.371 |
| `collatz` | 4.984 | 126.957 | **131.941** | 61.947 | 92.371 | 61.898 |
| `matmul` | 15.887 | 130.891 | **146.778** | 74.285 | 107.824 | 79.879 |
| `json_parse` | 49.306 | 502.868 | **552.174** | 108.768 | 164.359 | 158.379 |
| `nbody` | 16.996 | 141.118 | **158.114** | 74.796 | 129.919 | 95.645 |
| `chacha20` | 48.052 | 808.803 | **856.855** | 108.360 | 144.131 | 107.260 |
| `poly1305` | 33.901 | 278.022 | **311.923** | 89.054 | 144.736 | 122.332 |
| `blake2b` | 38.556 | 387.510 | **426.066** | 96.498 | 149.734 | 116.117 |
| `sha512` | 37.054 | 479.790 | **516.844** | 95.845 | 140.289 | 102.023 |
| `x25519` | 36.601 | 837.947 | **874.548** | 96.338 | 1236.472 | 494.282 |

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
