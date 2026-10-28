# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T03:38:10Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `c62921ec56d1d09741205e022e46c5d74ae88167` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40627240878 |
| NURL | `v0.79.1-8-gc62921ec` |
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
| _(floor: empty program)_ | _1.546_ | _1.476_ | _1.652_ | _22.785_ | _17.258_ |
| `lcg` | **39.051** | 39.061 | 39.205 | 1897.412 | 5218.898 |
| `packet_classifier` | 56.292 | **56.215** | 56.431 | 160.908 | 4446.037 |
| `ring_write` | 42.283 | **42.271** | 42.327 | 65.991 | 6413.441 |
| `histogram_bins` | 40.686 | **40.545** | 40.818 | 66.317 | 6052.694 |
| `prefix_scan` | **21.567** | 21.668 | 21.847 | 64.618 | 4528.272 |
| `binary_search` | 38.329 | **38.196** | 41.164 | 106.041 | 6745.039 |
| `sort_window` | 26.590 | **26.553** | 26.727 | 199.963 | 11892.519 |
| `bloom_filter` | **15.356** | 17.842 | 18.280 | 2829.062 | 7411.312 |
| `hash_join` | **26.896** | 27.942 | 29.326 | 3395.593 | 8469.154 |
| `sieve` | 20.180 | 20.065 | **20.032** | 67.949 | 3231.279 |
| `fib` | 29.924 | **29.837** | 30.102 | 132.283 | 1373.723 |
| `collatz` | 12.277 | **12.234** | 12.385 | 49.064 | 734.030 |
| `matmul` | 33.541 | **33.372** | 33.629 | 74.925 | 3071.892 |
| `json_parse` | **8.161** | 8.604 | 11.787 | 34.801 | 38.780 |
| `nbody` | 25.318 | 39.621 | **25.200** | 101.204 | 3169.736 |
| `chacha20` | **7.282** | 40.388 | 33.566 | n/a | n/a |
| `poly1305` | **11.819** | 31.767 | 21.149 | n/a | n/a |
| `blake2b` | **43.585** | 65.094 | 68.951 | n/a | n/a |
| `sha512` | **46.367** | 50.487 | 49.612 | n/a | n/a |
| `x25519` | **44.394** | 48.620 | 49.579 | n/a | n/a |

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
| _(floor: empty program)_ | _4.375_ | _111.534_ | _**115.909**_ | _61.356_ | _78.006_ | _53.980_ |
| `lcg` | 4.555 | 124.512 | **129.067** | 61.206 | 89.274 | 58.172 |
| `packet_classifier` | 4.728 | 126.010 | **130.738** | 62.560 | 89.023 | 58.164 |
| `ring_write` | 15.221 | 128.011 | **143.232** | 71.717 | 90.536 | 59.672 |
| `histogram_bins` | 15.320 | 130.126 | **145.446** | 72.733 | 109.179 | 68.217 |
| `prefix_scan` | 15.286 | 129.026 | **144.312** | 72.250 | 98.092 | 63.208 |
| `binary_search` | 15.717 | 128.865 | **144.582** | 72.982 | 92.038 | 63.934 |
| `sort_window` | 15.810 | 130.438 | **146.248** | 71.467 | 102.095 | 68.677 |
| `bloom_filter` | 16.275 | 131.249 | **147.524** | 72.650 | 100.933 | 65.841 |
| `hash_join` | 19.861 | 264.084 | **283.945** | 75.831 | 217.476 | 108.887 |
| `sieve` | 15.463 | 126.794 | **142.257** | 71.644 | 100.739 | 69.179 |
| `fib` | 4.739 | 126.513 | **131.252** | 61.514 | 90.803 | 58.328 |
| `collatz` | 4.764 | 129.234 | **133.998** | 61.436 | 90.644 | 59.802 |
| `matmul` | 16.713 | 128.708 | **145.421** | 73.237 | 104.360 | 79.622 |
| `json_parse` | 50.028 | 492.436 | **542.464** | 107.817 | 160.747 | 155.145 |
| `nbody` | 18.164 | 136.774 | **154.938** | 75.106 | 125.274 | 93.537 |
| `chacha20` | 57.412 | 759.411 | **816.823** | 114.529 | 141.126 | 104.791 |
| `poly1305` | 43.168 | 513.780 | **556.948** | 100.013 | 140.510 | 118.778 |
| `blake2b` | 39.008 | 378.857 | **417.865** | 94.700 | 145.464 | 115.706 |
| `sha512` | 38.685 | 479.120 | **517.805** | 95.330 | 137.110 | 101.246 |
| `x25519` | 39.398 | 833.093 | **872.491** | 95.368 | 1221.182 | 491.787 |

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
