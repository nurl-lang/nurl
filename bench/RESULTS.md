# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T08:37:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `76936505fdda19596b6d7b1250d8a2154f5aaf0b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40657293361 |
| NURL | `v0.79.1-27-g76936505` |
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
| _(floor: empty program)_ | _1.513_ | _1.429_ | _1.643_ | _22.996_ | _17.863_ |
| `lcg` | **39.237** | 39.371 | 39.548 | 1903.255 | 5023.046 |
| `packet_classifier` | 56.623 | **56.615** | 56.715 | 164.835 | 4407.802 |
| `ring_write` | 42.514 | **42.443** | 42.679 | 67.489 | 6463.849 |
| `histogram_bins` | **39.792** | 40.962 | 41.178 | 68.901 | 6182.450 |
| `prefix_scan` | **22.077** | 22.130 | 22.405 | 70.049 | 4441.426 |
| `binary_search` | 40.146 | **38.695** | 41.537 | 110.817 | 6209.098 |
| `sort_window` | 27.007 | **26.993** | 27.286 | 201.946 | 11267.244 |
| `bloom_filter` | **16.980** | 18.168 | 18.760 | 2853.141 | 7430.726 |
| `hash_join` | **27.170** | 28.488 | 29.564 | 3468.783 | 8396.156 |
| `sieve` | 20.895 | **20.197** | 20.884 | 70.012 | 3414.198 |
| `fib` | **25.429** | 30.149 | 30.135 | 134.808 | 1359.160 |
| `collatz` | 12.473 | **12.458** | 12.909 | 52.473 | 745.189 |
| `matmul` | 33.810 | **33.700** | 33.825 | 77.149 | 3506.559 |
| `json_parse` | **8.765** | 8.902 | 12.164 | 38.793 | 41.651 |
| `nbody` | **25.497** | 39.920 | 25.498 | 101.911 | 3150.507 |
| `chacha20` | **7.439** | 42.033 | 33.921 | n/a | n/a |
| `poly1305` | **11.999** | 32.071 | 21.438 | n/a | n/a |
| `blake2b` | **44.110** | 65.406 | 69.508 | n/a | n/a |
| `sha512` | **47.643** | 50.960 | 50.241 | n/a | n/a |
| `x25519` | **31.629** | 48.887 | 49.465 | n/a | n/a |

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
| _(floor: empty program)_ | _4.756_ | _120.479_ | _**125.235**_ | _65.543_ | _82.420_ | _54.893_ |
| `lcg` | 4.852 | 133.443 | **138.295** | 64.622 | 106.498 | 61.798 |
| `packet_classifier` | 5.032 | 131.255 | **136.287** | 63.843 | 92.943 | 59.745 |
| `ring_write` | 16.054 | 137.190 | **153.244** | 76.416 | 98.311 | 62.456 |
| `histogram_bins` | 15.518 | 133.058 | **148.576** | 73.716 | 112.316 | 70.199 |
| `prefix_scan` | 16.493 | 143.069 | **159.562** | 79.029 | 105.071 | 67.862 |
| `binary_search` | 16.908 | 142.489 | **159.397** | 79.816 | 100.762 | 69.755 |
| `sort_window` | 16.658 | 142.547 | **159.205** | 79.209 | 112.977 | 77.445 |
| `bloom_filter` | 17.130 | 141.833 | **158.963** | 77.228 | 106.856 | 70.664 |
| `hash_join` | 20.896 | 275.202 | **296.098** | 83.234 | 229.236 | 117.240 |
| `sieve` | 16.716 | 138.021 | **154.737** | 75.876 | 110.632 | 74.170 |
| `fib` | 5.269 | 134.393 | **139.662** | 65.870 | 96.606 | 62.987 |
| `collatz` | 5.094 | 137.846 | **142.940** | 66.521 | 97.354 | 62.757 |
| `matmul` | 17.758 | 136.233 | **153.991** | 78.183 | 111.040 | 80.338 |
| `json_parse` | 52.786 | 498.983 | **551.769** | 115.002 | 173.756 | 166.589 |
| `nbody` | 19.415 | 145.814 | **165.229** | 80.601 | 133.262 | 98.667 |
| `chacha20` | 58.282 | 774.532 | **832.814** | 119.081 | 144.693 | 107.953 |
| `poly1305` | 46.819 | 521.657 | **568.476** | 106.885 | 146.340 | 125.976 |
| `blake2b` | 40.521 | 383.726 | **424.247** | 100.049 | 150.828 | 117.475 |
| `sha512` | 40.507 | 484.120 | **524.627** | 100.397 | 143.158 | 104.237 |
| `x25519` | 55.171 | 1216.961 | **1272.132** | 115.199 | 1245.117 | 499.953 |

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
