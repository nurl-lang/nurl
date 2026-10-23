# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T16:03:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `e6c324cb352d46b3cb057127fc4c22ceffc1c255` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39982631973 |
| NURL | `v0.77.2-6-ge6c324cb` |
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
| _(floor: empty program)_ | _1.498_ | _1.465_ | _1.654_ | _23.054_ | _18.107_ |
| `lcg` | 39.242 | **39.226** | 39.379 | 1933.233 | 5064.842 |
| `packet_classifier` | 56.340 | **56.280** | 56.635 | 162.876 | 4322.687 |
| `ring_write` | 42.403 | **42.397** | 42.597 | 68.334 | 6446.383 |
| `histogram_bins` | 40.836 | **40.665** | 40.957 | 68.314 | 6174.286 |
| `prefix_scan` | **21.739** | 21.787 | 21.979 | 66.872 | 4476.115 |
| `binary_search` | 38.513 | **38.503** | 41.143 | 108.086 | 6322.726 |
| `sort_window` | **26.642** | 26.740 | 26.805 | 198.526 | 11397.927 |
| `bloom_filter` | **15.631** | 18.089 | 18.614 | 2853.088 | 7626.535 |
| `hash_join` | **27.272** | 28.286 | 29.451 | 3412.588 | 8438.373 |
| `sieve` | **19.026** | 20.824 | 21.016 | 70.920 | 3270.022 |
| `fib` | 30.009 | 29.995 | **29.968** | 133.033 | 1355.916 |
| `collatz` | 12.298 | **12.256** | 12.489 | 50.517 | 743.370 |
| `matmul` | 48.128 | **33.695** | 40.747 | 78.906 | 3158.037 |
| `json_parse` | **8.655** | 8.895 | 12.059 | 38.351 | 41.481 |
| `nbody` | 25.499 | 39.934 | **25.469** | 102.352 | 3088.852 |
| `chacha20` | **7.817** | 40.566 | 33.822 | n/a | n/a |
| `poly1305` | 23.730 | 31.974 | **21.316** | n/a | n/a |
| `blake2b` | **43.957** | 65.187 | 69.256 | n/a | n/a |
| `sha512` | **46.781** | 50.888 | 49.887 | n/a | n/a |
| `x25519` | **44.415** | 48.969 | 49.748 | n/a | n/a |

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
| _(floor: empty program)_ | _4.281_ | _114.394_ | _**118.675**_ | _64.641_ | _81.932_ | _53.097_ |
| `lcg` | 4.429 | 125.368 | **129.797** | 63.219 | 94.876 | 59.792 |
| `packet_classifier` | 4.543 | 122.541 | **127.084** | 61.923 | 92.726 | 58.734 |
| `ring_write` | 13.741 | 128.215 | **141.956** | 73.548 | 95.330 | 61.531 |
| `histogram_bins` | 14.030 | 129.954 | **143.984** | 73.151 | 112.373 | 68.562 |
| `prefix_scan` | 14.472 | 131.554 | **146.026** | 74.433 | 101.946 | 65.994 |
| `binary_search` | 14.120 | 126.406 | **140.526** | 72.666 | 96.507 | 64.641 |
| `sort_window` | 14.326 | 131.799 | **146.125** | 73.430 | 106.479 | 70.477 |
| `bloom_filter` | 14.633 | 132.063 | **146.696** | 72.369 | 101.522 | 65.749 |
| `hash_join` | 18.238 | 267.700 | **285.938** | 78.272 | 220.732 | 110.688 |
| `sieve` | 14.112 | 129.002 | **143.114** | 72.708 | 104.881 | 81.257 |
| `fib` | 4.759 | 128.206 | **132.965** | 65.168 | 92.927 | 59.911 |
| `collatz` | 4.757 | 128.391 | **133.148** | 64.057 | 103.480 | 62.550 |
| `matmul` | 15.811 | 134.650 | **150.461** | 76.258 | 110.496 | 80.656 |
| `json_parse` | 49.042 | 507.693 | **556.735** | 111.178 | 169.492 | 165.424 |
| `nbody` | 17.416 | 145.919 | **163.335** | 80.570 | 135.275 | 100.406 |
| `chacha20` | 49.923 | 828.026 | **877.949** | 111.322 | 146.397 | 109.977 |
| `poly1305` | 33.615 | 290.713 | **324.328** | 93.568 | 146.040 | 123.609 |
| `blake2b` | 38.236 | 390.387 | **428.623** | 100.021 | 156.117 | 119.928 |
| `sha512` | 39.066 | 497.195 | **536.261** | 102.830 | 149.453 | 105.394 |
| `x25519` | 37.954 | 846.078 | **884.032** | 99.185 | 1249.840 | 504.374 |

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
