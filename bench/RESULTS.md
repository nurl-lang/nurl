# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T14:18:23Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `5e37d18d2f8650436d40127e1d7d090f0877ac74` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40337459730 |
| NURL | `v0.78.0-24-g5e37d18d` |
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
| _(floor: empty program)_ | _1.445_ | _1.412_ | _1.603_ | _25.033_ | _17.357_ |
| `lcg` | 39.089 | **39.070** | 39.396 | 1880.736 | 5022.004 |
| `packet_classifier` | 56.262 | **56.175** | 56.490 | 163.067 | 4456.508 |
| `ring_write` | 42.263 | **42.165** | 42.305 | 66.416 | 6378.197 |
| `histogram_bins` | **40.645** | 40.730 | 40.917 | 67.484 | 6286.014 |
| `prefix_scan` | **21.700** | 21.791 | 22.172 | 69.433 | 4496.009 |
| `binary_search` | 38.271 | **38.244** | 40.957 | 107.320 | 6089.552 |
| `sort_window` | **26.596** | 26.669 | 26.848 | 199.468 | 11689.604 |
| `bloom_filter` | **15.371** | 17.760 | 18.257 | 2831.384 | 7915.162 |
| `hash_join` | **26.867** | 27.903 | 29.182 | 3528.555 | 8262.553 |
| `sieve` | 22.422 | **17.646** | 17.901 | 65.747 | 3481.439 |
| `fib` | **30.070** | 30.107 | 30.217 | 132.936 | 1346.873 |
| `collatz` | 12.335 | **12.274** | 12.446 | 51.022 | 742.643 |
| `matmul` | 33.634 | **33.494** | 33.776 | 78.245 | 3090.711 |
| `json_parse` | **8.038** | 8.541 | 11.692 | 36.965 | 39.577 |
| `nbody` | **25.190** | 39.864 | 25.226 | 101.573 | 3094.791 |
| `chacha20` | **7.365** | 40.600 | 33.883 | n/a | n/a |
| `poly1305` | **11.877** | 31.908 | 21.068 | n/a | n/a |
| `blake2b` | **43.826** | 65.692 | 69.356 | n/a | n/a |
| `sha512` | **46.808** | 50.616 | 49.382 | n/a | n/a |
| `x25519` | **44.648** | 48.496 | 49.369 | n/a | n/a |

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
| _(floor: empty program)_ | _4.257_ | _113.272_ | _**117.529**_ | _63.173_ | _79.786_ | _54.936_ |
| `lcg` | 4.668 | 126.792 | **131.460** | 62.504 | 90.102 | 57.381 |
| `packet_classifier` | 4.597 | 125.417 | **130.014** | 62.170 | 91.137 | 58.645 |
| `ring_write` | 15.126 | 131.427 | **146.553** | 73.873 | 94.364 | 60.323 |
| `histogram_bins` | 15.399 | 136.774 | **152.173** | 76.210 | 111.849 | 67.354 |
| `prefix_scan` | 15.248 | 132.546 | **147.794** | 74.310 | 101.858 | 64.189 |
| `binary_search` | 15.535 | 131.646 | **147.181** | 74.083 | 96.172 | 66.310 |
| `sort_window` | 16.120 | 136.480 | **152.600** | 75.684 | 106.865 | 69.934 |
| `bloom_filter` | 16.137 | 134.359 | **150.496** | 74.810 | 105.643 | 67.220 |
| `hash_join` | 19.773 | 267.099 | **286.872** | 78.718 | 219.223 | 110.495 |
| `sieve` | 15.347 | 129.716 | **145.063** | 73.478 | 104.196 | 70.217 |
| `fib` | 4.637 | 128.871 | **133.508** | 63.862 | 93.829 | 59.680 |
| `collatz` | 4.757 | 128.623 | **133.380** | 62.777 | 93.792 | 59.883 |
| `matmul` | 17.007 | 133.284 | **150.291** | 75.983 | 107.877 | 78.406 |
| `json_parse` | 50.665 | 491.470 | **542.135** | 109.476 | 163.829 | 158.219 |
| `nbody` | 18.060 | 139.432 | **157.492** | 76.046 | 128.205 | 93.575 |
| `chacha20` | 56.675 | 819.274 | **875.949** | 114.791 | 140.956 | 105.029 |
| `poly1305` | 44.864 | 525.505 | **570.369** | 108.107 | 144.619 | 121.268 |
| `blake2b` | 39.324 | 382.753 | **422.077** | 97.443 | 146.770 | 113.863 |
| `sha512` | 39.629 | 481.761 | **521.390** | 98.146 | 139.375 | 100.202 |
| `x25519` | 39.289 | 835.890 | **875.179** | 96.965 | 1219.121 | 495.927 |

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
