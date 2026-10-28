# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T01:40:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16366512 KiB |
| Commit | `85f2e34f9543d0864cee75520fc6a4048d7c08e1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40615924520 |
| NURL | `v0.79.1-3-g85f2e34f` |
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
| _(floor: empty program)_ | _1.160_ | _1.139_ | _1.240_ | _19.625_ | _13.830_ |
| `lcg` | 35.089 | **34.976** | 35.168 | 1396.260 | 3711.399 |
| `packet_classifier` | **61.164** | 61.322 | 61.199 | 152.916 | 3125.164 |
| `ring_write` | 39.521 | **39.485** | 39.895 | 59.410 | 4553.878 |
| `histogram_bins` | 37.138 | **36.810** | 36.999 | 61.339 | 4287.255 |
| `prefix_scan` | 19.872 | **19.812** | 20.110 | 58.427 | 3186.715 |
| `binary_search` | **27.994** | 28.174 | 36.941 | 100.374 | 4644.825 |
| `sort_window` | 37.197 | **36.136** | 39.379 | 167.711 | 8538.210 |
| `bloom_filter` | 13.859 | **13.701** | 14.127 | 2258.782 | 5694.685 |
| `hash_join` | **23.073** | 24.641 | 24.592 | 2867.537 | 6701.123 |
| `sieve` | 38.070 | 38.548 | **38.007** | 85.166 | 2488.094 |
| `fib` | 28.498 | 29.078 | **28.355** | 108.424 | 853.737 |
| `collatz` | 14.871 | **14.770** | 15.484 | 57.466 | 542.965 |
| `matmul` | 19.218 | 19.941 | **18.937** | 71.266 | 2436.333 |
| `json_parse` | **6.534** | 7.176 | 9.283 | 31.054 | 32.368 |
| `nbody` | **21.188** | 30.065 | 21.616 | 80.803 | 1961.506 |
| `chacha20` | **7.605** | 35.662 | 30.964 | n/a | n/a |
| `poly1305` | **13.274** | 33.010 | 22.009 | n/a | n/a |
| `blake2b` | **40.418** | 45.505 | 49.562 | n/a | n/a |
| `sha512` | **39.806** | 41.283 | 42.528 | n/a | n/a |
| `x25519` | **35.633** | 40.183 | 39.264 | n/a | n/a |

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
| _(floor: empty program)_ | _3.720_ | _90.477_ | _**94.197**_ | _48.247_ | _57.981_ | _49.531_ |
| `lcg` | 3.680 | 97.306 | **100.986** | 47.366 | 63.075 | 53.977 |
| `packet_classifier` | 3.961 | 99.972 | **103.933** | 49.522 | 69.594 | 56.770 |
| `ring_write` | 13.176 | 99.836 | **113.012** | 56.811 | 64.886 | 56.672 |
| `histogram_bins` | 13.274 | 101.530 | **114.804** | 57.863 | 82.328 | 64.654 |
| `prefix_scan` | 13.214 | 105.220 | **118.434** | 59.173 | 75.054 | 61.392 |
| `binary_search` | 13.616 | 99.164 | **112.780** | 58.795 | 67.849 | 59.071 |
| `sort_window` | 13.540 | 106.904 | **120.444** | 58.886 | 80.124 | 69.581 |
| `bloom_filter` | 14.937 | 113.921 | **128.858** | 63.804 | 80.452 | 67.758 |
| `hash_join` | 16.726 | 218.424 | **235.150** | 63.248 | 171.947 | 108.650 |
| `sieve` | 14.624 | 113.205 | **127.829** | 65.916 | 86.293 | 75.483 |
| `fib` | 4.418 | 107.487 | **111.905** | 52.770 | 71.293 | 59.627 |
| `collatz` | 4.360 | 112.128 | **116.488** | 54.956 | 77.496 | 62.164 |
| `matmul` | 16.105 | 115.599 | **131.704** | 67.119 | 85.164 | 83.544 |
| `json_parse` | 45.148 | 412.915 | **458.063** | 95.786 | 131.938 | 161.096 |
| `nbody` | 16.646 | 117.715 | **134.361** | 65.584 | 105.798 | 96.604 |
| `chacha20` | 48.951 | 646.124 | **695.075** | 99.053 | 118.750 | 109.874 |
| `poly1305` | 39.001 | 439.790 | **478.791** | 88.311 | 119.065 | 122.272 |
| `blake2b` | 34.897 | 326.766 | **361.663** | 85.031 | 116.601 | 117.198 |
| `sha512` | 34.625 | 399.150 | **433.775** | 84.061 | 113.600 | 104.035 |
| `x25519` | 34.826 | 733.012 | **767.838** | 84.306 | 1099.302 | 469.058 |

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
