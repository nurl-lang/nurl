# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T04:29:44Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `f4f7917878066b547c22e80e53340726d6e6c4a4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40817463998 |
| NURL | `v0.80.0-34-gf4f79178` |
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
| _(floor: empty program)_ | _1.618_ | _1.569_ | _1.873_ | _29.282_ | _20.659_ |
| `lcg` | **39.633** | 39.642 | 39.845 | 1873.518 | 5410.781 |
| `packet_classifier` | **56.642** | 56.787 | 57.103 | 164.684 | 4469.365 |
| `ring_write` | **42.627** | 42.711 | 42.858 | 70.599 | 6377.037 |
| `histogram_bins` | **39.953** | 41.106 | 41.246 | 71.357 | 6035.366 |
| `prefix_scan` | 22.127 | **22.013** | 22.149 | 69.818 | 4711.411 |
| `binary_search` | 39.919 | **38.770** | 41.263 | 111.583 | 6155.771 |
| `sort_window` | 26.925 | **26.846** | 27.075 | 200.539 | 12558.179 |
| `bloom_filter` | **16.898** | 18.335 | 18.847 | 2872.267 | 7541.249 |
| `hash_join` | **27.294** | 28.428 | 29.634 | 3499.226 | 8273.284 |
| `sieve` | 25.884 | 25.501 | **22.014** | 72.068 | 3169.694 |
| `fib` | **25.398** | 29.927 | 30.257 | 133.445 | 1356.840 |
| `collatz` | 12.371 | **12.218** | 12.661 | 51.525 | 745.727 |
| `matmul` | 33.660 | **33.434** | 33.744 | 77.679 | 3232.585 |
| `json_parse` | **8.475** | 8.934 | 12.002 | 36.989 | 39.328 |
| `nbody` | **25.359** | 40.124 | 25.592 | 106.891 | 3082.984 |
| `chacha20` | **7.433** | 42.450 | 34.052 | n/a | n/a |
| `poly1305` | **11.694** | 32.007 | 21.327 | n/a | n/a |
| `blake2b` | **44.142** | 65.189 | 69.500 | n/a | n/a |
| `sha512` | **47.625** | 51.114 | 49.632 | n/a | n/a |
| `x25519` | **31.677** | 48.799 | 49.749 | n/a | n/a |

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
| _(floor: empty program)_ | _4.979_ | _136.384_ | _**141.363**_ | _75.224_ | _103.077_ | _76.342_ |
| `lcg` | 5.473 | 153.716 | **159.189** | 74.367 | 105.125 | 82.785 |
| `packet_classifier` | 5.324 | 149.094 | **154.418** | 74.485 | 107.616 | 83.127 |
| `ring_write` | 15.778 | 143.173 | **158.951** | 83.635 | 110.514 | 85.449 |
| `histogram_bins` | 16.210 | 146.877 | **163.087** | 80.912 | 122.839 | 87.380 |
| `prefix_scan` | 15.962 | 147.204 | **163.166** | 80.893 | 110.177 | 87.067 |
| `binary_search` | 16.153 | 144.467 | **160.620** | 80.642 | 105.593 | 84.588 |
| `sort_window` | 16.465 | 148.576 | **165.041** | 78.502 | 116.291 | 93.475 |
| `bloom_filter` | 17.549 | 148.948 | **166.497** | 82.019 | 116.516 | 86.941 |
| `hash_join` | 20.640 | 282.741 | **303.381** | 90.008 | 241.301 | 136.403 |
| `sieve` | 16.248 | 148.181 | **164.429** | 78.047 | 115.645 | 98.806 |
| `fib` | 5.361 | 149.307 | **154.668** | 74.307 | 105.910 | 79.332 |
| `collatz` | 5.505 | 143.239 | **148.744** | 71.037 | 103.773 | 77.787 |
| `matmul` | 17.772 | 144.125 | **161.897** | 82.482 | 118.497 | 101.440 |
| `json_parse` | 51.449 | 486.124 | **537.573** | 116.015 | 169.585 | 183.925 |
| `nbody` | 18.670 | 144.924 | **163.594** | 81.191 | 140.809 | 115.885 |
| `chacha20` | 59.202 | 778.174 | **837.376** | 123.802 | 156.212 | 129.422 |
| `poly1305` | 45.139 | 528.809 | **573.948** | 108.606 | 154.241 | 145.027 |
| `blake2b` | 40.147 | 391.880 | **432.027** | 105.689 | 162.836 | 143.598 |
| `sha512` | 39.865 | 486.459 | **526.324** | 103.105 | 152.960 | 127.701 |
| `x25519` | 54.836 | 1311.599 | **1366.435** | 119.670 | 1245.682 | 521.522 |

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
