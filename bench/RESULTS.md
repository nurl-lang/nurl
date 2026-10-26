# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T08:29:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `7265293d5cab492e5dc9e313b2b2e80c9bc9c95f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40291928406 |
| NURL | `v0.78.0-8-g7265293d` |
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
| _(floor: empty program)_ | _1.472_ | _1.428_ | _1.647_ | _23.984_ | _17.073_ |
| `lcg` | 39.235 | 39.249 | **39.192** | 1886.576 | 4987.494 |
| `packet_classifier` | 56.186 | **56.108** | 56.390 | 161.479 | 4618.744 |
| `ring_write` | 42.114 | **42.062** | 42.296 | 63.724 | 6358.362 |
| `histogram_bins` | **40.507** | 40.520 | 40.686 | 64.881 | 6081.587 |
| `prefix_scan` | **21.558** | 21.636 | 21.783 | 65.571 | 4472.913 |
| `binary_search` | **38.294** | 38.663 | 40.802 | 105.563 | 6355.224 |
| `sort_window` | 26.595 | **26.540** | 26.836 | 197.404 | 11102.991 |
| `bloom_filter` | **15.354** | 17.810 | 18.458 | 2863.703 | 7802.423 |
| `hash_join` | **26.889** | 27.783 | 29.195 | 3399.030 | 8344.345 |
| `sieve` | 19.864 | 19.991 | **19.786** | 65.152 | 3284.992 |
| `fib` | 29.827 | **29.684** | 29.988 | 133.182 | 1375.731 |
| `collatz` | 12.245 | **12.181** | 12.420 | 48.190 | 740.233 |
| `matmul` | 33.318 | **33.239** | 33.411 | 75.554 | 3146.112 |
| `json_parse` | **8.315** | 8.585 | 11.761 | 36.045 | 37.934 |
| `nbody` | **25.155** | 39.726 | 25.254 | 100.250 | 3153.601 |
| `chacha20` | **7.276** | 41.869 | 33.587 | n/a | n/a |
| `poly1305` | **11.680** | 31.728 | 21.068 | n/a | n/a |
| `blake2b` | **43.476** | 64.898 | 69.573 | n/a | n/a |
| `sha512` | **47.457** | 50.478 | 49.445 | n/a | n/a |
| `x25519` | **44.243** | 48.550 | 49.421 | n/a | n/a |

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
| _(floor: empty program)_ | _4.263_ | _109.305_ | _**113.568**_ | _61.422_ | _79.635_ | _52.395_ |
| `lcg` | 4.483 | 125.594 | **130.077** | 62.404 | 89.334 | 58.140 |
| `packet_classifier` | 4.597 | 122.766 | **127.363** | 61.099 | 88.641 | 58.331 |
| `ring_write` | 13.858 | 125.367 | **139.225** | 70.722 | 90.232 | 59.653 |
| `histogram_bins` | 13.796 | 125.198 | **138.994** | 70.334 | 107.126 | 66.027 |
| `prefix_scan` | 13.903 | 127.721 | **141.624** | 71.213 | 95.851 | 62.345 |
| `binary_search` | 14.158 | 126.333 | **140.491** | 70.869 | 92.419 | 64.249 |
| `sort_window` | 14.344 | 129.257 | **143.601** | 71.886 | 102.408 | 68.915 |
| `bloom_filter` | 14.581 | 131.763 | **146.344** | 72.498 | 100.648 | 65.202 |
| `hash_join` | 18.164 | 266.266 | **284.430** | 75.366 | 217.459 | 109.132 |
| `sieve` | 14.080 | 125.208 | **139.288** | 70.354 | 100.328 | 68.076 |
| `fib` | 4.654 | 121.410 | **126.064** | 60.792 | 88.117 | 58.676 |
| `collatz` | 4.741 | 123.706 | **128.447** | 60.715 | 90.701 | 58.485 |
| `matmul` | 15.442 | 125.073 | **140.515** | 71.638 | 103.459 | 77.113 |
| `json_parse` | 47.696 | 487.844 | **535.540** | 104.483 | 159.069 | 153.558 |
| `nbody` | 16.806 | 135.525 | **152.331** | 73.287 | 124.241 | 93.101 |
| `chacha20` | 55.444 | 812.432 | **867.876** | 111.605 | 139.470 | 103.591 |
| `poly1305` | 41.513 | 507.782 | **549.295** | 97.646 | 140.963 | 119.203 |
| `blake2b` | 36.418 | 376.928 | **413.346** | 92.236 | 146.195 | 114.282 |
| `sha512` | 36.934 | 474.892 | **511.826** | 94.021 | 138.282 | 100.421 |
| `x25519` | 36.921 | 830.345 | **867.266** | 92.772 | 1211.311 | 491.037 |

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
