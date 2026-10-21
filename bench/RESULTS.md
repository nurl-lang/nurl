# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-21T14:50:07Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `790926410f4d90614deabfa032c40ee2a33e2306` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39619412617 |
| NURL | `v0.76.0-15-g79092641` |
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
| _(floor: empty program)_ | _1.451_ | _1.427_ | _1.618_ | _22.133_ | _17.220_ |
| `lcg` | **39.086** | 39.169 | 39.225 | 1903.278 | 5069.250 |
| `packet_classifier` | **56.261** | 56.272 | 56.393 | 162.216 | 4306.070 |
| `ring_write` | **42.286** | 42.431 | 42.425 | 66.619 | 6444.937 |
| `histogram_bins` | **39.552** | 40.771 | 40.900 | 67.466 | 6226.412 |
| `prefix_scan` | 21.754 | **21.671** | 21.957 | 66.071 | 4695.331 |
| `binary_search` | **36.487** | 38.325 | 40.909 | 107.518 | 6699.774 |
| `sort_window` | **26.547** | 26.671 | 26.857 | 197.110 | 11635.413 |
| `bloom_filter` | **15.941** | 17.984 | 18.652 | 2851.782 | 7787.920 |
| `hash_join` | **27.343** | 28.075 | 29.369 | 3547.144 | 8341.872 |
| `sieve` | 18.874 | 18.359 | **18.301** | 67.037 | 3558.816 |
| `fib` | 30.058 | **30.043** | 30.422 | 133.538 | 1361.002 |
| `collatz` | 12.351 | **12.350** | 12.620 | 53.019 | 759.182 |
| `matmul` | 33.550 | **33.421** | 33.691 | 76.883 | 3360.235 |
| `json_parse` | **8.255** | 8.529 | 11.940 | 36.866 | 40.408 |
| `nbody` | **25.263** | 39.822 | 26.124 | 101.141 | 3185.271 |
| `chacha20` | **7.451** | 42.352 | 33.867 | n/a | n/a |
| `poly1305` | 23.470 | 31.901 | **21.076** | n/a | n/a |
| `blake2b` | **43.640** | 65.059 | 69.338 | n/a | n/a |
| `sha512` | **47.391** | 50.578 | 49.525 | n/a | n/a |
| `x25519` | **44.381** | 48.714 | 49.639 | n/a | n/a |

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
| _(floor: empty program)_ | _4.251_ | _105.184_ | _**109.435**_ | _64.217_ | _78.636_ | _53.180_ |
| `lcg` | 4.346 | 113.495 | **117.841** | 60.427 | 89.459 | 59.406 |
| `packet_classifier` | 4.366 | 114.748 | **119.114** | 60.941 | 91.455 | 58.584 |
| `ring_write` | 13.040 | 117.048 | **130.088** | 69.541 | 90.555 | 62.181 |
| `histogram_bins` | 13.248 | 125.132 | **138.380** | 71.732 | 110.431 | 66.392 |
| `prefix_scan` | 13.515 | 123.278 | **136.793** | 70.526 | 100.328 | 63.073 |
| `binary_search` | 13.558 | 119.776 | **133.334** | 70.815 | 94.652 | 66.275 |
| `sort_window` | 13.771 | 122.523 | **136.294** | 72.062 | 103.302 | 69.860 |
| `bloom_filter` | 14.091 | 122.587 | **136.678** | 70.894 | 101.977 | 65.368 |
| `hash_join` | 18.520 | 269.610 | **288.130** | 76.286 | 224.202 | 113.368 |
| `sieve` | 13.624 | 118.685 | **132.309** | 70.707 | 103.766 | 69.967 |
| `fib` | 4.793 | 118.149 | **122.942** | 64.408 | 93.574 | 59.322 |
| `collatz` | 4.905 | 121.712 | **126.617** | 64.603 | 95.229 | 60.353 |
| `matmul` | 15.449 | 122.961 | **138.410** | 75.477 | 110.768 | 81.612 |
| `json_parse` | 46.781 | 492.972 | **539.753** | 106.373 | 162.917 | 157.152 |
| `nbody` | 16.011 | 139.628 | **155.639** | 73.336 | 127.201 | 95.697 |
| `chacha20` | 47.032 | 820.957 | **867.989** | 105.799 | 142.070 | 107.306 |
| `poly1305` | 31.810 | 270.991 | **302.801** | 89.498 | 143.507 | 120.905 |
| `blake2b` | 36.004 | 382.809 | **418.813** | 93.959 | 146.706 | 117.155 |
| `sha512` | 36.225 | 482.262 | **518.487** | 94.998 | 141.635 | 102.903 |
| `x25519` | 40.055 | 730.269 | **770.324** | 99.515 | 1229.892 | 498.466 |

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
